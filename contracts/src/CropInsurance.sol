// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {RainOracle} from "./RainOracle.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Crop Insurance  (module 14, part two) — parametric cover
/// @notice Problem: a farmer's field dries out, they file a claim, and then wait while an
///         assessor decides whether the loss was real and how much it was worth. The wait
///         is the product failing exactly when it is needed.
/// @dev    **Parametric** insurance pays on a measurement, not on a loss. If the rainfall
///         for the insured period comes in under the trigger, the policy pays its full
///         coverage — no assessor, no negotiation, no discretion. Settlement takes one
///         transaction that anybody may send.
///
///         The trade is honest and worth arguing about in class: you give up accuracy to
///         get speed and certainty. A farmer whose crop survived a dry spell still gets
///         paid; a farmer ruined by something other than drought gets nothing. That gap
///         between the measurement and the actual loss is called **basis risk**, and it is
///         the reason parametric cover suits some risks and not others.
///
///         Two rules keep the contract solvent and honest:
///
///         **Reserve before you sell.** Every policy's full coverage is locked against the
///         pool the moment it is bought. An insurer that sells more cover than it holds is
///         solvent only while claims stay rare — which is precisely not when they arrive.
///
///         **Insure the future only.** A policy may only cover a period that has not
///         started. Otherwise anyone could watch the drought happen, then buy cover for it.
contract CropInsurance is AccessControl, Stamping {
    using SafeERC20 for IERC20;

    uint16 public constant MODULE_ID = 14;

    uint16 public constant MIN_PREMIUM_BPS = 100; // 1%
    uint16 public constant MAX_PREMIUM_BPS = 5000; // 50%

    enum Status {
        None,
        Active,
        PaidOut,
        Expired // the period was fine, or the rain came — cover released back to the pool
    }

    struct Policy {
        address holder;
        uint256 coverage;
        uint256 premium;
        uint32 period; // the period insured
        uint32 triggerMm; // frozen at purchase, so later admin changes cannot move it
        Status status;
    }

    IERC20 public immutable token;
    RainOracle public immutable oracle;

    /// Rain below this, over the insured period, is a drought. Applies to new policies only.
    uint32 public triggerMm;
    uint16 public premiumBps;

    /// Coverage promised to live policies. The pool may never be spent below this.
    uint256 public reserved;

    Policy[] private _policies; // index + 1 == public id
    mapping(address => uint256[]) private _byHolder;

    event PoolFunded(address indexed from, uint256 amount, uint256 balance);
    event PolicyBought(
        uint256 indexed id,
        address indexed holder,
        uint32 indexed period,
        uint256 coverage,
        uint256 premium,
        uint32 triggerMm
    );
    event PolicySettled(uint256 indexed id, address indexed holder, bool paid, uint32 mm, uint256 amount);
    event TermsChanged(uint32 triggerMm, uint16 premiumBps);

    error ZeroAmount();
    error NoSuchPolicy();
    error PeriodAlreadyStarted();
    error NotEnoughInThePool(uint256 available, uint256 wanted);
    error AlreadySettled();
    error NoReadingYet();
    error BadTerms();

    constructor(
        IERC20 token_,
        RainOracle oracle_,
        address admin,
        uint32 triggerMm_,
        uint16 premiumBps_,
        TrustvillePassport passport_
    ) Stamping(passport_) {
        if (premiumBps_ < MIN_PREMIUM_BPS || premiumBps_ > MAX_PREMIUM_BPS) revert BadTerms();
        token = token_;
        oracle = oracle_;
        triggerMm = triggerMm_;
        premiumBps = premiumBps_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ------------------------------------------------------------------- the pool */

    /// Anyone may capitalise the insurer — the town, a charity, a class of students.
    /// Premiums land here too, which is the whole business model in one line.
    function fund(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit PoolFunded(msg.sender, amount, token.balanceOf(address(this)));
    }

    /// What the insurer could still promise: everything it holds, minus what it has
    /// already promised to live policies.
    function available() public view returns (uint256) {
        uint256 held = token.balanceOf(address(this));
        return held > reserved ? held - reserved : 0;
    }

    /* ---------------------------------------------------------------- the policies */

    /// Buy cover for a period that has not begun. The premium goes into the pool and the
    /// coverage is reserved out of it immediately.
    function buy(uint32 period, uint256 coverage) external returns (uint256 id) {
        if (coverage == 0) revert ZeroAmount();
        if (period <= oracle.currentPeriod()) revert PeriodAlreadyStarted();

        uint256 free = available();
        if (coverage > free) revert NotEnoughInThePool(free, coverage);

        uint256 premium = (coverage * premiumBps) / 10_000;
        reserved += coverage;

        _policies.push(
            Policy({
                holder: msg.sender,
                coverage: coverage,
                premium: premium,
                period: period,
                triggerMm: triggerMm,
                status: Status.Active
            })
        );
        id = _policies.length;
        _byHolder[msg.sender].push(id);

        if (premium > 0) token.safeTransferFrom(msg.sender, address(this), premium);
        emit PolicyBought(id, msg.sender, period, coverage, premium, _policies[id - 1].triggerMm);
        _stamp(msg.sender, MODULE_ID);
    }

    /// Settlement is a measurement, not a decision. Anyone may trigger it — the sender
    /// cannot change the outcome, and a holder who has lost their phone still gets paid.
    function settle(uint256 id) external returns (bool paid) {
        Policy storage p = _at(id);
        if (p.status != Status.Active) revert AlreadySettled();

        (bool finalized, uint32 mm,) = oracle.reading(p.period);
        if (!finalized) revert NoReadingYet();

        reserved -= p.coverage;
        paid = mm < p.triggerMm;
        p.status = paid ? Status.PaidOut : Status.Expired;

        if (paid) token.safeTransfer(p.holder, p.coverage);
        emit PolicySettled(id, p.holder, paid, mm, paid ? p.coverage : 0);
    }

    /// Terms apply to policies bought afterwards. Live policies keep the trigger they were
    /// sold with — an insurer that could move the goalposts after taking the premium is
    /// not selling insurance.
    function setTerms(uint32 triggerMm_, uint16 premiumBps_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (premiumBps_ < MIN_PREMIUM_BPS || premiumBps_ > MAX_PREMIUM_BPS) revert BadTerms();
        triggerMm = triggerMm_;
        premiumBps = premiumBps_;
        emit TermsChanged(triggerMm_, premiumBps_);
    }

    /// Profit the pool may pay out to its funders: never the reserved cover.
    function withdrawSurplus(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 free = available();
        if (amount > free) revert NotEnoughInThePool(free, amount);
        token.safeTransfer(to, amount);
    }

    /* --------------------------------------------------------------------- views */

    function count() external view returns (uint256) {
        return _policies.length;
    }

    function get(uint256 id) external view returns (Policy memory) {
        return _at(id);
    }

    function policiesOf(address holder) external view returns (uint256[] memory) {
        return _byHolder[holder];
    }

    function quote(uint256 coverage) external view returns (uint256) {
        return (coverage * premiumBps) / 10_000;
    }

    function _at(uint256 id) private view returns (Policy storage) {
        if (id == 0 || id > _policies.length) revert NoSuchPolicy();
        return _policies[id - 1];
    }
}
