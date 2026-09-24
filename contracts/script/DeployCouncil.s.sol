// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TownGovernor} from "../src/TownGovernor.sol";
import {TownTimelock} from "../src/TownTimelock.sol";
import {TownTreasury} from "../src/TownTreasury.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D3b — the Council (modules 11-12).
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployCouncil.s.sol --rpc-url didlab --account didlab-deployer \
///     --legacy --broadcast
///
/// Timings default to a lab session: 1 min voting delay, 10 min voting, 2 min timelock.
/// Override with VOTING_DELAY / VOTING_PERIOD / TIMELOCK_DELAY (seconds).
///
/// The deployer is the Timelock's admin only while this script runs, exactly as in D1:
/// it wires the roles and then renounces, leaving the Timelock owned by nobody.
contract DeployCouncil is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        uint48 votingDelay = uint48(vm.envOr("VOTING_DELAY", uint256(60)));
        uint32 votingPeriod = uint32(vm.envOr("VOTING_PERIOD", uint256(600)));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(120));
        uint256 threshold = vm.envOr("TREASURY_THRESHOLD", uint256(1));

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address voteTokenAddr = vm.parseJsonAddress(json, ".contracts.VoteToken");
        require(passportAddr != address(0) && voteTokenAddr != address(0), "D1/D3a not deployed");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        address[] memory none = new address[](0);
        TownTimelock timelock = new TownTimelock(timelockDelay, none, none, deployer);
        TownGovernor governor =
            new TownGovernor(IVotes(voteTokenAddr), timelock, votingDelay, votingPeriod, 0);

        // Only the Governor may schedule; anyone may execute a matured proposal; nobody
        // keeps admin rights over the Timelock afterwards.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        address[] memory owners = new address[](1);
        owners[0] = townAdmin; // the admin adds student signers through the multisig itself
        TownTreasury treasury = new TownTreasury(owners, threshold, TrustvillePassport(passportAddr));
        vm.stopBroadcast();

        require(!timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer), "timelock still has an admin");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "governor cannot propose");

        _record("TownTimelock", address(timelock));
        _record("TownGovernor", address(governor));
        _record("TownTreasury", address(treasury));

        console.log("");
        console.log("Voting delay / period / timelock (seconds):", votingDelay, votingPeriod, timelockDelay);
        console.log("Timelock holds the governed funds. Send it TVD to give the Council something to spend.");
        console.log("NEXT, as the ADMIN:");
        console.log(
            string.concat(
                'cast send ',
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(treasury)),
                " --rpc-url didlab --legacy --interactive"
            )
        );
        console.log("The Governor and Timelock need no passport role.");
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
