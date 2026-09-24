// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title Trustville Timelock — the Council's treasury and its waiting period
/// @notice This contract holds the town's governed funds. The Council (module 12) can only
///         ask it to act, and only after a proposal has passed; the Timelock then waits
///         before doing anything.
/// @dev    The delay is the point. A DAO without one can pass and execute a hostile
///         proposal in the same breath; with one, anyone who disagrees has time to see it
///         coming and get out. Deployment wires it so that:
///           PROPOSER  = the Governor only
///           EXECUTOR  = address(0), meaning anyone may execute a queued, matured proposal
///           ADMIN     = nobody, after the deployer renounces
contract TownTimelock is TimelockController {
    constructor(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        TimelockController(minDelay, proposers, executors, admin)
    {}
}
