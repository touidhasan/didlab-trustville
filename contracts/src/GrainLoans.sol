// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stamping} from "./Stamping.sol";
import {TownSwap} from "./TownSwap.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Grain Loans  (module 15, part two) — borrowing against collateral
///
/// @notice ⚠ THIS CONTRACT CONTAINS A DELIBERATE VULNERABILITY. ⚠
///
///         It prices collateral with `TownSwap.unsafeSpotTvdPerGrain()` — the pool's spot
///         price, read at the instant of the call. That price can be moved by anyone with
///         enough capital, *within a single transaction*: swap to push GRAIN up, borrow
///         against the inflated collateral, swap back, walk away from the loan. The pool
///         is left holding collateral worth far less than the debt.
///
///         `test_ATTACK_InflateTheCollateralPriceAndWalkAway` performs exactly that and
///         passes. It is not a failing test to be fixed — it is the exploit, working,
///         kept as the module's centrepiece. `docs/modules/15-defi.md` sets the exercise.
///
///         Do not copy this pricing into anything real. The three standard fixes, and what
///         each of them costs, are in the guide.
///
/// @dev    Everything else here is ordinary and intended to be correct: an over-
///         collateralised loan, a supply pool whose shares appreciate with interest, and
///         liquidation with a bonus that pays someone to do the unpleasant job of closing
///         a bad position.
///
///         Why over-collateralise at all? Because the contract cannot sue you. There is no
///         identity behind a borrower and no court to pursue, so the only enforcement is
///         collateral worth more than the loan. That constraint — not greed — is why on-
///         chain lending looks so different from a mortgage.
contract GrainLoans is AccessControl, Stamping {
    using SafeERC20 for IERC20;

    uint16 public constant MODULE_ID = 15;

    /// Borrow up to 50% of collateral value.
    uint256 public constant LTV_BPS = 5_000;
    /// Liquidatable once debt passes 70% of collateral value.
    uint256 public constant LIQUIDATION_BPS = 7_000;
    /// A liquidator receives 10% more collateral than the debt they repay.
    uint256 public constant LIQUIDATION_BONUS_BPS = 1_000;

    uint256 public constant MAX_RATE_BPS = 5_000; // 50% a year, ceiling
    uint256 public constant YEAR = 365 days;

    IERC20 public immutable tvd;
    IERC20 public immutable grain;
    TownSwap public immutable swap;

    uint256 public rateBps; // simple interest, per year

    struct Position {
        uint256 collateral; // GRAIN
        uint256 debt; // TVD, including interest accrued so far
        uint64 accruedAt;
    }

    mapping(address => Position) private _positions;

    uint256 public totalDebt;
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    event Supplied(address indexed who, uint256 amount, uint256 shares);
    event Withdrawn(address indexed who, uint256 shares, uint256 amount);
    event CollateralDeposited(address indexed who, uint256 amount);
    event CollateralWithdrawn(address indexed who, uint256 amount);
    event Borrowed(address indexed who, uint256 amount, uint256 debt, uint256 price);
    event Repaid(address indexed who, uint256 amount, uint256 debt);
    event Liquidated(
        address indexed borrower, address indexed liquidator, uint256 repaid, uint256 seized, uint256 price
    );
    event RateChanged(uint256 rateBps);

    error ZeroAmount();
    error NothingSupplied();
    error NotEnoughShares(uint256 have, uint256 want);
    error NotEnoughCash(uint256 available, uint256 wanted);
    error WouldBeUndercollateralised(uint256 debt, uint256 maxDebt);
    error NotLiquidatable(uint256 debt, uint256 threshold);
    error RepayingTooMuch(uint256 debt, uint256 offered);
    error NoDebt();
    error BadRate();

    constructor(
        IERC20 tvd_,
        IERC20 grain_,
        TownSwap swap_,
        address admin,
        uint256 rateBps_,
        TrustvillePassport passport_
    ) Stamping(passport_) {
        if (rateBps_ > MAX_RATE_BPS) revert BadRate();
        tvd = tvd_;
        grain = grain_;
        swap = swap_;
        rateBps = rateBps_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ------------------------------------------------------------------ lenders */

    /// Cash sitting here, plus what is owed to it. A share is worth its slice of both.
    function poolValue() public view returns (uint256) {
        return tvd.balanceOf(address(this)) + totalDebt;
    }

    function supply(uint256 amount) external returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        uint256 value = poolValue();
        shares = totalShares == 0 || value == 0 ? amount : (amount * totalShares) / value;
        if (shares == 0) revert ZeroAmount();

        totalShares += shares;
        sharesOf[msg.sender] += shares;
        tvd.safeTransferFrom(msg.sender, address(this), amount);
        emit Supplied(msg.sender, amount, shares);
    }

    /// Lenders can only take out cash that is actually here. If it is all lent out, they
    /// wait for a repayment — which is the liquidity risk every lending pool carries.
    function withdrawSupply(uint256 shares) external returns (uint256 amount) {
        uint256 have = sharesOf[msg.sender];
        if (shares == 0) revert ZeroAmount();
        if (shares > have) revert NotEnoughShares(have, shares);

        amount = (poolValue() * shares) / totalShares;
        uint256 cash = tvd.balanceOf(address(this));
        if (amount > cash) revert NotEnoughCash(cash, amount);

        sharesOf[msg.sender] = have - shares;
        totalShares -= shares;
        tvd.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, shares, amount);
    }

    /* ---------------------------------------------------------------- borrowers */

    function depositCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _accrue(msg.sender);
        _positions[msg.sender].collateral += amount;
        grain.safeTransferFrom(msg.sender, address(this), amount);
        emit CollateralDeposited(msg.sender, amount);
    }

    function withdrawCollateral(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _accrue(msg.sender);
        Position storage p = _positions[msg.sender];
        p.collateral -= amount; // underflow reverts: you cannot take out what is not there

        uint256 maxDebt = (_valueOf(p.collateral) * LTV_BPS) / 10_000;
        if (p.debt > maxDebt) revert WouldBeUndercollateralised(p.debt, maxDebt);

        grain.safeTransfer(msg.sender, amount);
        emit CollateralWithdrawn(msg.sender, amount);
    }

    /// @dev The vulnerable line is `_valueOf`, which reads the AMM's spot price.
    function borrow(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _accrue(msg.sender);
        Position storage p = _positions[msg.sender];

        uint256 cash = tvd.balanceOf(address(this));
        if (amount > cash) revert NotEnoughCash(cash, amount);

        uint256 newDebt = p.debt + amount;
        uint256 maxDebt = (_valueOf(p.collateral) * LTV_BPS) / 10_000;
        if (newDebt > maxDebt) revert WouldBeUndercollateralised(newDebt, maxDebt);

        p.debt = newDebt;
        totalDebt += amount;

        tvd.safeTransfer(msg.sender, amount);
        emit Borrowed(msg.sender, amount, newDebt, swap.unsafeSpotTvdPerGrain());
        _stamp(msg.sender, MODULE_ID);
    }

    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        _accrue(msg.sender);
        Position storage p = _positions[msg.sender];
        if (p.debt == 0) revert NoDebt();
        if (amount > p.debt) revert RepayingTooMuch(p.debt, amount);

        p.debt -= amount;
        totalDebt -= amount;
        tvd.safeTransferFrom(msg.sender, address(this), amount);
        emit Repaid(msg.sender, amount, p.debt);
    }

    /* -------------------------------------------------------------- liquidation */

    /// Anybody may close a position that has gone past the threshold, and is paid a bonus
    /// in collateral for doing it. The bonus is not generosity: without it nobody would
    /// spend gas cleaning up somebody else's loss, and bad debt would simply sit there.
    function liquidate(address borrower, uint256 repayAmount) external returns (uint256 seized) {
        if (repayAmount == 0) revert ZeroAmount();
        _accrue(borrower);
        Position storage p = _positions[borrower];

        uint256 threshold = (_valueOf(p.collateral) * LIQUIDATION_BPS) / 10_000;
        if (p.debt <= threshold) revert NotLiquidatable(p.debt, threshold);
        if (repayAmount > p.debt) revert RepayingTooMuch(p.debt, repayAmount);

        uint256 price = swap.unsafeSpotTvdPerGrain();
        seized = (repayAmount * 1e18 * (10_000 + LIQUIDATION_BONUS_BPS)) / (price * 10_000);
        if (seized > p.collateral) seized = p.collateral; // a bad position pays what it can

        p.debt -= repayAmount;
        p.collateral -= seized;
        totalDebt -= repayAmount;

        tvd.safeTransferFrom(msg.sender, address(this), repayAmount);
        grain.safeTransfer(msg.sender, seized);
        emit Liquidated(borrower, msg.sender, repayAmount, seized, price);
    }

    /* -------------------------------------------------------------------- views */

    function positionOf(address who) external view returns (uint256 collateral, uint256 debt) {
        Position storage p = _positions[who];
        return (p.collateral, p.debt + _interest(p));
    }

    /// TVD this borrower could still take out, at the price right now.
    function availableToBorrow(address who) external view returns (uint256) {
        Position storage p = _positions[who];
        uint256 maxDebt = (_valueOf(p.collateral) * LTV_BPS) / 10_000;
        uint256 debt = p.debt + _interest(p);
        return maxDebt > debt ? maxDebt - debt : 0;
    }

    /// Below 1e18 means liquidatable. Exactly the number a borrower should be watching.
    function healthFactor(address who) external view returns (uint256) {
        Position storage p = _positions[who];
        uint256 debt = p.debt + _interest(p);
        if (debt == 0) return type(uint256).max;
        return (_valueOf(p.collateral) * LIQUIDATION_BPS * 1e18) / (debt * 10_000);
    }

    function setRate(uint256 rateBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (rateBps_ > MAX_RATE_BPS) revert BadRate();
        rateBps = rateBps_;
        emit RateChanged(rateBps_);
    }

    /* ------------------------------------------------------------------ internal */

    /// @dev HERE IS THE BUG. The spot price of an AMM is not a price feed: it is a
    ///      snapshot of one pool's reserves, and reserves are exactly what a trader can
    ///      change. See the module guide.
    function _valueOf(uint256 grainAmount) private view returns (uint256) {
        if (grainAmount == 0) return 0;
        return (grainAmount * swap.unsafeSpotTvdPerGrain()) / 1e18;
    }

    function _interest(Position storage p) private view returns (uint256) {
        if (p.debt == 0 || p.accruedAt == 0) return 0;
        uint256 elapsed = block.timestamp - p.accruedAt;
        return (p.debt * rateBps * elapsed) / (10_000 * YEAR);
    }

    /// Interest is folded into the debt whenever a position is touched. A position nobody
    /// touches accrues nothing into `totalDebt` until someone does — a simplification, and
    /// one of the exercises is to replace it with a global index.
    function _accrue(address who) private {
        Position storage p = _positions[who];
        uint256 interest = _interest(p);
        if (interest > 0) {
            p.debt += interest;
            totalDebt += interest;
        }
        p.accruedAt = uint64(block.timestamp);
    }
}
