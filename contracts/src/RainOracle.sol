// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Rain Oracle  (module 14, part one) — how an outside fact gets on chain
/// @notice Problem: a contract cannot look out of the window. Everything it knows, somebody
///         told it. So the interesting question is never "what was the rainfall" but "whose
///         claim about the rainfall are we willing to act on, and what happens when they
///         are wrong".
/// @dev    This is the module where the chain stops being self-contained. Modules 1–13 are
///         true by construction: a token balance is whatever the contract says it is. A
///         rainfall figure is true only if a person or a machine outside reported it
///         honestly. No amount of cryptography fixes that — it only changes who you have
///         to trust and how visible their mistakes are.
///
///         The design here: several reporters submit independently for a period, and the
///         contract takes the **median**, not the mean. A mean lets one reporter drag the
///         answer as far as they like — report a million and the average is ruined. With a
///         median, a single liar moves the result by at most one position in the sorted
///         list, and to control the answer outright an attacker must control more than half
///         the reporters. That is the whole argument for M-of-N, in one sentence.
///
///         What this still does not fix, and the guide says so plainly:
///         - reporters who all read the *same* broken weather station agree perfectly;
///         - reporters who can see each other's submissions can copy rather than measure
///           (module 6's commit–reveal is the fix, and it is an exercise here);
///         - if reporters simply stop, the contract has no reading and no way to demand one.
///
///         Liveness and honesty pull in opposite directions: a low quorum keeps the oracle
///         answering and makes it easier to capture; a high one is harder to capture and
///         easier to stall.
contract RainOracle is AccessControl {
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    uint32 public constant MIN_QUORUM = 2;
    uint32 public constant MAX_REPORTS = 9; // keeps the on-chain sort cheap and bounded

    /// How long one reporting period lasts. 10 minutes suits a lab; a day suits reality.
    uint32 public immutable periodSeconds;

    struct Reading {
        uint32 mm; // the agreed figure, once finalised
        uint32 count; // how many reports it was drawn from
        bool finalized;
    }

    uint32 public quorum;

    mapping(uint32 => Reading) private _readings;
    mapping(uint32 => uint32[]) private _reports;
    mapping(uint32 => address[]) private _reporters;
    mapping(uint32 => mapping(address => bool)) public hasReported;

    event Reported(uint32 indexed period, address indexed reporter, uint32 mm, uint32 count);
    event Finalized(uint32 indexed period, uint32 mm, uint32 count, address by);
    event QuorumChanged(uint32 quorum);

    error BadPeriod();
    error PeriodNotOver();
    error AlreadyFinalized();
    error AlreadyReported();
    error TooManyReports();
    error NotEnoughReports(uint32 have, uint32 need);
    error BadQuorum();

    constructor(address admin, uint32 periodSeconds_, uint32 quorum_) {
        if (periodSeconds_ < 60) revert BadPeriod();
        if (quorum_ < MIN_QUORUM || quorum_ > MAX_REPORTS) revert BadQuorum();
        periodSeconds = periodSeconds_;
        quorum = quorum_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function currentPeriod() public view returns (uint32) {
        return uint32(block.timestamp / periodSeconds);
    }

    /// A reporter may only report a period that has finished. Nobody reports the future —
    /// that would let a reporter with a policy in hand write their own payout.
    function report(uint32 period, uint32 mm) external onlyRole(REPORTER_ROLE) {
        if (period >= currentPeriod()) revert PeriodNotOver();
        if (_readings[period].finalized) revert AlreadyFinalized();
        if (hasReported[period][msg.sender]) revert AlreadyReported();
        if (_reports[period].length >= MAX_REPORTS) revert TooManyReports();

        hasReported[period][msg.sender] = true;
        _reports[period].push(mm);
        _reporters[period].push(msg.sender);
        emit Reported(period, msg.sender, mm, uint32(_reports[period].length));
    }

    /// Anyone may finalise once enough reports are in — including someone with a policy
    /// riding on the answer, because the caller cannot influence what the answer is.
    function finalize(uint32 period) external returns (uint32 mm) {
        Reading storage r = _readings[period];
        if (r.finalized) revert AlreadyFinalized();

        uint32 n = uint32(_reports[period].length);
        if (n < quorum) revert NotEnoughReports(n, quorum);

        mm = _median(_reports[period]);
        r.mm = mm;
        r.count = n;
        r.finalized = true;
        emit Finalized(period, mm, n, msg.sender);
    }

    /// The reading a policy acts on. `finalized` false means "no answer yet" — never zero
    /// dressed up as a drought.
    function reading(uint32 period) external view returns (bool finalized, uint32 mm, uint32 count) {
        Reading storage r = _readings[period];
        return (r.finalized, r.mm, r.count);
    }

    /// Every individual submission stays readable after the fact, on purpose: a reporter
    /// whose number sat far from the median is visible to everyone, for ever.
    function reportsOf(uint32 period)
        external
        view
        returns (address[] memory who, uint32[] memory mm)
    {
        return (_reporters[period], _reports[period]);
    }

    function reporterCount(uint32 period) external view returns (uint256) {
        return _reports[period].length;
    }

    function setQuorum(uint32 quorum_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (quorum_ < MIN_QUORUM || quorum_ > MAX_REPORTS) revert BadQuorum();
        quorum = quorum_;
        emit QuorumChanged(quorum_);
    }

    /// Insertion sort on a copy. At most nine elements, so this is cheap — and it must
    /// never reorder the stored array, which is the audit trail of who said what.
    function _median(uint32[] storage values) private view returns (uint32) {
        uint256 n = values.length;
        uint32[] memory a = new uint32[](n);
        for (uint256 i; i < n; i++) a[i] = values[i];

        for (uint256 i = 1; i < n; i++) {
            uint32 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                j--;
            }
            a[j] = key;
        }
        // Even counts take the lower of the two middles: deterministic, and it never
        // invents a figure no reporter submitted.
        return a[(n - 1) / 2];
    }
}
