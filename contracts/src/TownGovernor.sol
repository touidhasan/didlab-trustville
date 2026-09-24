// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Trustville Council  (module 12) — token-voted governance
/// @notice Problem: decisions made behind a door, and spending nobody can check. Voting in
///         public is easy; making the *result* binding is the hard part.
/// @dev    The Council does not hold the money. The Timelock does, and the Timelock only
///         accepts instructions from a proposal that actually passed. That indirection is
///         the whole design: a vote is not advisory, it is the only path to the treasury.
///
///         Four phases, each with a reason to exist:
///           voting delay   — a snapshot everyone can see before voting opens, so nobody
///                            buys tokens after reading a proposal
///           voting period   — the window to cast a vote
///           timelock delay  — time to react if a passing proposal is hostile; whoever
///                            disagrees can exit before it executes
///           execution       — anyone may push the button; the vote is the authority
///
///         Voting power comes from vTVD at the snapshot, and only if it was DELEGATED.
contract TownGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// Every proposal id, so the UI can list them without an indexer.
    uint256[] private _proposalIds;

    constructor(IVotes token_, TimelockController timelock_, uint48 votingDelay_, uint32 votingPeriod_, uint256 proposalThreshold_)
        Governor("Trustville Council")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(4) // 4% of wrapped supply must vote
        GovernorTimelockControl(timelock_)
    {}

    function proposalIds() external view returns (uint256[] memory) {
        return _proposalIds;
    }

    function proposalCount() external view returns (uint256) {
        return _proposalIds.length;
    }

    /// Recent proposals, newest first — enough for the classroom UI.
    function recentProposals(uint256 limit) external view returns (uint256[] memory ids) {
        uint256 n = _proposalIds.length;
        uint256 take = limit < n ? limit : n;
        ids = new uint256[](take);
        for (uint256 i; i < take; i++) {
            ids[i] = _proposalIds[n - 1 - i];
        }
    }

    /* ----------------------------------------------------------- overrides */

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override returns (uint256 proposalId) {
        proposalId = super._propose(targets, values, calldatas, description, proposer);
        _proposalIds.push(proposalId);
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
