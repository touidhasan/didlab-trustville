// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Charity  (module 13) — milestone crowdfunding
/// @notice Problem: you give to a cause and then have no idea whether the money was
///         spent on it. The usual answer is to trust the organiser, or to trust a
///         platform that holds the money and charges for the privilege.
/// @dev    Two ideas do the work here.
///
///         **All-or-nothing.** Pledges sit in the contract until the goal is met. Miss
///         the deadline and every donor takes their own money back — nobody has to be
///         asked, and no organiser decides who gets refunded.
///
///         **Tranches against evidence.** Meeting the goal does not hand over the money.
///         The beneficiary publishes a hash of their evidence for one milestone at a
///         time, an arbiter approves it, and only that tranche is released. If a
///         milestone is rejected, the campaign stops and donors reclaim what is left,
///         pro rata.
///
///         Every payment out of this contract is a **pull**: the recipient calls and
///         takes it. Nothing loops over a list of donors paying each one, because a
///         single reverting recipient in such a loop freezes everyone else's money.
///         This is the pattern that makes the famous reentrancy exercises boring.
///
///         What a blockchain does NOT fix: the evidence itself. A hash proves the
///         document has not changed since it was posted; it says nothing about whether
///         the receipts are real. That judgement stays human, which is why there is an
///         arbiter — and why the module guide asks students who should hold that role.
contract TownCharity is AccessControl, Stamping {
    using SafeERC20 for IERC20;

    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    uint16 public constant MODULE_ID = 13;

    uint64 public constant MIN_WINDOW = 5 minutes;
    uint64 public constant MAX_WINDOW = 90 days;
    uint256 public constant MIN_MILESTONES = 2;
    uint256 public constant MAX_MILESTONES = 5;

    enum State {
        None,
        Raising, // accepting pledges
        Funded, // goal met, milestones in progress
        Completed, // every milestone approved and paid
        Failed, // deadline passed under goal — donors refund in full
        Cancelled // a milestone was rejected — donors refund what is left
    }

    enum Step {
        Waiting, // not yet evidenced
        Submitted, // evidence posted, arbiter has not ruled
        Approved, // paid
        Rejected
    }

    struct Milestone {
        uint256 amount;
        string what;
        bytes32 evidence; // hash of the off-chain report; never the report itself
        Step step;
    }

    struct Campaign {
        address beneficiary;
        string cause;
        uint256 goal;
        uint256 raised;
        uint256 released;
        uint64 deadline;
        State state;
    }

    IERC20 public immutable token;

    Campaign[] private _campaigns; // index + 1 == public id
    mapping(uint256 => Milestone[]) private _milestones;
    mapping(uint256 => mapping(address => uint256)) public pledgeOf;
    mapping(uint256 => mapping(address => bool)) public refunded;
    mapping(address => uint256[]) private _supported;

    event CampaignCreated(
        uint256 indexed id, address indexed beneficiary, uint256 goal, uint64 deadline, string cause
    );
    event Pledged(uint256 indexed id, address indexed donor, uint256 amount, uint256 raised);
    event GoalReached(uint256 indexed id, uint256 raised);
    event EvidenceSubmitted(uint256 indexed id, uint256 indexed step, bytes32 evidence);
    event MilestoneApproved(uint256 indexed id, uint256 indexed step, uint256 amount, address arbiter);
    event MilestoneRejected(uint256 indexed id, uint256 indexed step, string reason, address arbiter);
    event CampaignFailed(uint256 indexed id, uint256 raised, uint256 goal);
    event Refund(uint256 indexed id, address indexed donor, uint256 amount);
    event Completed(uint256 indexed id, uint256 total);

    error BadWindow();
    error BadMilestones();
    error MilestonesDoNotSumToGoal(uint256 sum, uint256 goal);
    error NoSuchCampaign();
    error NotRaising();
    error NotFunded();
    error ZeroAmount();
    error Overfunded(uint256 remaining);
    error NotTheBeneficiary();
    error NoSuchMilestone();
    error WrongStep();
    error TooEarly();
    error NothingToRefund();
    error AlreadyRefunded();

    constructor(IERC20 token_, address admin, TrustvillePassport passport_) Stamping(passport_) {
        token = token_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin);
    }

    /* ------------------------------------------------------------------ raising */

    /// Anyone may start a campaign. The milestone amounts must add up to the goal, so a
    /// donor can read exactly what their money is being promised to before giving it.
    function create(
        string calldata cause,
        uint256 goal,
        uint64 window,
        uint256[] calldata amounts,
        string[] calldata what
    ) external returns (uint256 id) {
        if (window < MIN_WINDOW || window > MAX_WINDOW) revert BadWindow();
        if (goal == 0) revert ZeroAmount();
        if (
            amounts.length != what.length || amounts.length < MIN_MILESTONES
                || amounts.length > MAX_MILESTONES
        ) revert BadMilestones();

        uint256 sum;
        for (uint256 i; i < amounts.length; i++) {
            if (amounts[i] == 0) revert ZeroAmount();
            sum += amounts[i];
        }
        if (sum != goal) revert MilestonesDoNotSumToGoal(sum, goal);

        _campaigns.push(
            Campaign({
                beneficiary: msg.sender,
                cause: cause,
                goal: goal,
                raised: 0,
                released: 0,
                deadline: uint64(block.timestamp) + window,
                state: State.Raising
            })
        );
        id = _campaigns.length;
        for (uint256 i; i < amounts.length; i++) {
            _milestones[id].push(
                Milestone({amount: amounts[i], what: what[i], evidence: bytes32(0), step: Step.Waiting})
            );
        }
        emit CampaignCreated(id, msg.sender, goal, _campaigns[id - 1].deadline, cause);
    }

    /// Pledges are capped at exactly what is still needed: no surplus to argue over, and
    /// the arithmetic a donor checks is the arithmetic the contract does.
    function pledge(uint256 id, uint256 amount) external {
        Campaign storage c = _at(id);
        if (c.state != State.Raising) revert NotRaising();
        if (block.timestamp >= c.deadline) revert NotRaising();
        if (amount == 0) revert ZeroAmount();

        uint256 remaining = c.goal - c.raised;
        if (amount > remaining) revert Overfunded(remaining);

        if (pledgeOf[id][msg.sender] == 0) _supported[msg.sender].push(id);
        pledgeOf[id][msg.sender] += amount;
        c.raised += amount;

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Pledged(id, msg.sender, amount, c.raised);

        if (c.raised == c.goal) {
            c.state = State.Funded;
            emit GoalReached(id, c.raised);
        }
        _stamp(msg.sender, MODULE_ID);
    }

    /// Anyone may close a campaign that ran out of time under its goal. It is deliberately
    /// not the beneficiary's decision, and it costs the caller nothing but gas.
    function closeFailed(uint256 id) external {
        Campaign storage c = _at(id);
        if (c.state != State.Raising) revert NotRaising();
        if (block.timestamp < c.deadline) revert TooEarly();
        c.state = State.Failed;
        emit CampaignFailed(id, c.raised, c.goal);
    }

    /* --------------------------------------------------------------- milestones */

    /// The beneficiary posts the hash of their report. The report lives off chain — a
    /// public ledger is the wrong place for receipts with names on them.
    function submitEvidence(uint256 id, uint256 step, bytes32 evidence) external {
        Campaign storage c = _at(id);
        if (c.state != State.Funded) revert NotFunded();
        if (msg.sender != c.beneficiary) revert NotTheBeneficiary();
        if (step >= _milestones[id].length) revert NoSuchMilestone();
        if (evidence == bytes32(0)) revert WrongStep();

        Milestone storage m = _milestones[id][step];
        if (m.step != Step.Waiting) revert WrongStep();
        m.evidence = evidence;
        m.step = Step.Submitted;
        emit EvidenceSubmitted(id, step, evidence);
    }

    /// Approving releases exactly one tranche. The arbiter never holds the money and
    /// cannot choose a different recipient or a different amount.
    function approveMilestone(uint256 id, uint256 step) external onlyRole(ARBITER_ROLE) {
        Campaign storage c = _at(id);
        if (c.state != State.Funded) revert NotFunded();
        if (step >= _milestones[id].length) revert NoSuchMilestone();

        Milestone storage m = _milestones[id][step];
        if (m.step != Step.Submitted) revert WrongStep();
        m.step = Step.Approved;
        c.released += m.amount;

        bool last = c.released == c.goal;
        if (last) c.state = State.Completed;

        token.safeTransfer(c.beneficiary, m.amount);
        emit MilestoneApproved(id, step, m.amount, msg.sender);
        if (last) emit Completed(id, c.released);
    }

    /// Rejecting stops the campaign. Everything already approved stays paid — that work
    /// was done — and the rest becomes refundable.
    function rejectMilestone(uint256 id, uint256 step, string calldata reason)
        external
        onlyRole(ARBITER_ROLE)
    {
        Campaign storage c = _at(id);
        if (c.state != State.Funded) revert NotFunded();
        if (step >= _milestones[id].length) revert NoSuchMilestone();

        Milestone storage m = _milestones[id][step];
        if (m.step != Step.Submitted) revert WrongStep();
        m.step = Step.Rejected;
        c.state = State.Cancelled;
        emit MilestoneRejected(id, step, reason, msg.sender);
    }

    /* ------------------------------------------------------------------ refunds */

    /// A failed campaign refunds in full; a cancelled one refunds each donor their share
    /// of what was never released. The donor calls this themselves — the contract never
    /// pushes money at a list of addresses.
    function refund(uint256 id) external {
        Campaign storage c = _at(id);
        if (c.state != State.Failed && c.state != State.Cancelled) revert NotRaising();
        if (refunded[id][msg.sender]) revert AlreadyRefunded();

        uint256 pledged = pledgeOf[id][msg.sender];
        if (pledged == 0) revert NothingToRefund();

        uint256 owed = c.state == State.Failed ? pledged : (pledged * (c.raised - c.released)) / c.raised;
        refunded[id][msg.sender] = true;
        if (owed == 0) revert NothingToRefund();

        token.safeTransfer(msg.sender, owed);
        emit Refund(id, msg.sender, owed);
    }

    /// What this donor can still take out, without sending a transaction to find out.
    function refundable(uint256 id, address donor) external view returns (uint256) {
        Campaign storage c = _at(id);
        if (refunded[id][donor]) return 0;
        uint256 pledged = pledgeOf[id][donor];
        if (pledged == 0) return 0;
        if (c.state == State.Failed) return pledged;
        if (c.state == State.Cancelled) return (pledged * (c.raised - c.released)) / c.raised;
        return 0;
    }

    /* -------------------------------------------------------------------- views */

    function count() external view returns (uint256) {
        return _campaigns.length;
    }

    function get(uint256 id) external view returns (Campaign memory) {
        return _at(id);
    }

    function milestonesOf(uint256 id) external view returns (Milestone[] memory) {
        return _milestones[id];
    }

    function supportedBy(address donor) external view returns (uint256[] memory) {
        return _supported[donor];
    }

    function _at(uint256 id) private view returns (Campaign storage) {
        if (id == 0 || id > _campaigns.length) revert NoSuchCampaign();
        return _campaigns[id - 1];
    }
}
