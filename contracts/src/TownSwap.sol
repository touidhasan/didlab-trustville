// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Swap  (module 15, part one) — a constant-product market
/// @notice Problem: a farmer holds GRAIN and owes TVD. Selling means finding someone who
///         wants exactly what you have, at the moment you have it. Order books solve that
///         with a matching engine and somebody to run it.
/// @dev    An automated market maker replaces the counterparty with a formula. The pool
///         holds both assets and always obeys
///
///             x · y = k
///
///         so it will trade with anyone, at a price set by what it currently holds. Take
///         GRAIN out and GRAIN becomes scarcer in the pool, so the next unit costs more.
///         Nobody sets the price; the ratio of the reserves *is* the price.
///
///         Three consequences worth drawing out in class, all visible in the tests:
///
///         **Slippage.** The price you get is worse than the price you saw, and worse the
///         larger your trade relative to the pool. That is not a bug or a fee — it is the
///         curve. `quote()` tells you the real number before you sign, and `minOut` is
///         how you refuse a worse one.
///
///         **Fees accrue to liquidity providers.** 0.3% of every input stays in the pool.
///         Shares are not reprinted, so each share is worth slightly more afterwards.
///
///         **Providing liquidity is a position, not a deposit.** Put in both assets, and
///         the pool sells whichever one is rising. Come back after a big move and you hold
///         more of the loser and less of the winner than you started with — less than if
///         you had simply held. That is impermanent loss, and a test here measures it.
contract TownSwap is Stamping {
    using SafeERC20 for IERC20;

    uint16 public constant MODULE_ID = 15;
    uint256 public constant FEE_BPS = 30; // 0.3%, charged on the way in
    uint256 public constant MINIMUM_LIQUIDITY = 1000; // burned on the first deposit

    IERC20 public immutable tvd;
    IERC20 public immutable grain;

    uint256 public reserveTvd;
    uint256 public reserveGrain;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    event LiquidityAdded(address indexed who, uint256 tvd, uint256 grain, uint256 shares);
    event LiquidityRemoved(address indexed who, uint256 tvd, uint256 grain, uint256 shares);
    event Swapped(
        address indexed who, bool tvdIn, uint256 amountIn, uint256 amountOut, uint256 reserveTvd, uint256 reserveGrain
    );

    error ZeroAmount();
    error NoLiquidity();
    error WrongRatio(uint256 expectedGrain);
    error NotEnoughShares(uint256 have, uint256 want);
    error TooLittleOut(uint256 got, uint256 wanted);
    error Expired();

    constructor(IERC20 tvd_, IERC20 grain_, TrustvillePassport passport_) Stamping(passport_) {
        tvd = tvd_;
        grain = grain_;
    }

    /* --------------------------------------------------------------- liquidity */

    /// The first deposit sets the price — whatever ratio you put in is what the pool
    /// believes the assets are worth. Afterwards deposits must match the current ratio, or
    /// they would move the price and hand the difference to arbitrage.
    function addLiquidity(uint256 amountTvd, uint256 maxGrain, uint256 deadline)
        external
        returns (uint256 shares)
    {
        _notExpired(deadline);
        if (amountTvd == 0 || maxGrain == 0) revert ZeroAmount();

        uint256 amountGrain;
        if (totalShares == 0) {
            amountGrain = maxGrain;
            shares = Math.sqrt(amountTvd * amountGrain);
            if (shares <= MINIMUM_LIQUIDITY) revert ZeroAmount();
            // A sliver is burned for ever so the pool can never be emptied to zero shares,
            // which is what makes the first depositor's price manipulable elsewhere.
            shares -= MINIMUM_LIQUIDITY;
            totalShares = MINIMUM_LIQUIDITY;
        } else {
            amountGrain = (amountTvd * reserveGrain) / reserveTvd;
            if (amountGrain > maxGrain) revert WrongRatio(amountGrain);
            shares = (amountTvd * totalShares) / reserveTvd;
            if (shares == 0) revert ZeroAmount();
        }

        totalShares += shares;
        sharesOf[msg.sender] += shares;
        reserveTvd += amountTvd;
        reserveGrain += amountGrain;

        tvd.safeTransferFrom(msg.sender, address(this), amountTvd);
        grain.safeTransferFrom(msg.sender, address(this), amountGrain);
        emit LiquidityAdded(msg.sender, amountTvd, amountGrain, shares);
    }

    /// Take out your share of whatever the pool holds NOW — not what you put in.
    function removeLiquidity(uint256 shares, uint256 deadline)
        external
        returns (uint256 outTvd, uint256 outGrain)
    {
        _notExpired(deadline);
        uint256 have = sharesOf[msg.sender];
        if (shares == 0) revert ZeroAmount();
        if (shares > have) revert NotEnoughShares(have, shares);

        outTvd = (reserveTvd * shares) / totalShares;
        outGrain = (reserveGrain * shares) / totalShares;

        sharesOf[msg.sender] = have - shares;
        totalShares -= shares;
        reserveTvd -= outTvd;
        reserveGrain -= outGrain;

        tvd.safeTransfer(msg.sender, outTvd);
        grain.safeTransfer(msg.sender, outGrain);
        emit LiquidityRemoved(msg.sender, outTvd, outGrain, shares);
    }

    /* -------------------------------------------------------------------- swaps */

    /// x·y = k, with the fee taken off the input. Read it as: whatever you put in, the
    /// pool keeps k at least as large as it was.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert NoLiquidity();
        uint256 inAfterFee = amountIn * (10_000 - FEE_BPS);
        return (inAfterFee * reserveOut) / (reserveIn * 10_000 + inAfterFee);
    }

    /// What this trade would actually give you, right now. Always check before signing:
    /// the headline price is the price of an infinitely small trade, which is not yours.
    function quote(uint256 amountIn, bool tvdIn) external view returns (uint256) {
        return tvdIn
            ? getAmountOut(amountIn, reserveTvd, reserveGrain)
            : getAmountOut(amountIn, reserveGrain, reserveTvd);
    }

    function swapTvdForGrain(uint256 amountIn, uint256 minOut, uint256 deadline)
        external
        returns (uint256 out)
    {
        _notExpired(deadline);
        out = getAmountOut(amountIn, reserveTvd, reserveGrain);
        if (out < minOut) revert TooLittleOut(out, minOut);

        reserveTvd += amountIn;
        reserveGrain -= out;

        tvd.safeTransferFrom(msg.sender, address(this), amountIn);
        grain.safeTransfer(msg.sender, out);
        emit Swapped(msg.sender, true, amountIn, out, reserveTvd, reserveGrain);
        _stamp(msg.sender, MODULE_ID);
    }

    function swapGrainForTvd(uint256 amountIn, uint256 minOut, uint256 deadline)
        external
        returns (uint256 out)
    {
        _notExpired(deadline);
        out = getAmountOut(amountIn, reserveGrain, reserveTvd);
        if (out < minOut) revert TooLittleOut(out, minOut);

        reserveGrain += amountIn;
        reserveTvd -= out;

        grain.safeTransferFrom(msg.sender, address(this), amountIn);
        tvd.safeTransfer(msg.sender, out);
        emit Swapped(msg.sender, false, amountIn, out, reserveTvd, reserveGrain);
        _stamp(msg.sender, MODULE_ID);
    }

    /* -------------------------------------------------------------------- price */

    /// @notice How many TVD one GRAIN is worth, according to the pool at this instant.
    /// @dev    **This number can be moved by anyone with enough capital, inside a single
    ///         transaction.** A large swap shifts the reserves, and the reserves are the
    ///         price. Any contract that makes a decision on this value — how much someone
    ///         may borrow, whether a position is safe to liquidate — can be lied to by a
    ///         borrower who swaps immediately before, and swaps back immediately after.
    ///
    ///         The name says so because module 15's lending half reads this on purpose,
    ///         and a test there carries out the attack. Read `docs/modules/15-defi.md`
    ///         before using it for anything that matters.
    function unsafeSpotTvdPerGrain() external view returns (uint256) {
        if (reserveGrain == 0) revert NoLiquidity();
        return (reserveTvd * 1e18) / reserveGrain;
    }

    /// The constant the pool defends. It only ever grows, by the fees.
    function k() external view returns (uint256) {
        return reserveTvd * reserveGrain;
    }

    function _notExpired(uint256 deadline) private view {
        if (deadline != 0 && block.timestamp > deadline) revert Expired();
    }
}
