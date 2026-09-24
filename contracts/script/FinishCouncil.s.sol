// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TownGovernor} from "../src/TownGovernor.sol";
import {TownTimelock} from "../src/TownTimelock.sol";
import {TownTreasury} from "../src/TownTreasury.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D3b, part two — finish a Council deployment whose Timelock and Governor are
/// already on chain.
///
/// `DeployCouncil.s.sol` deploys four contracts in one broadcast. If any transaction in
/// the middle fails, re-running it would orphan the contracts that *did* deploy and build
/// a second Council beside the first. This script picks up instead: it takes the existing
/// Timelock and Governor, deploys only the Treasury, records all three, and then checks
/// the wiring.
///
///   cd contracts
///   export TOWN_ADMIN=0x...      # the admin that will hold the multisig seat
///   export TIMELOCK=0x...        # already deployed
///   export GOVERNOR=0x...        # already deployed
///   forge script script/FinishCouncil.s.sol --rpc-url didlab --account didlab-deployer \
///     --legacy --slow --gas-estimate-multiplier 105 --broadcast
///
/// Renouncing the Timelock's admin role is NOT done here — see the README: it is a
/// refund-heavy transaction that this chain's gas estimator under-prices, so it is sent on
/// its own with an explicit gas limit. This script refuses to finish while that is pending.
contract FinishCouncil is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        TownTimelock timelock = TownTimelock(payable(vm.envAddress("TIMELOCK")));
        TownGovernor governor = TownGovernor(payable(vm.envAddress("GOVERNOR")));
        uint256 threshold = vm.envOr("TREASURY_THRESHOLD", uint256(1));

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        address passportAddr = vm.parseJsonAddress(vm.readFile(path), ".contracts.TrustvillePassport");
        require(passportAddr != address(0), "D1 not deployed");

        // Read the wiring BEFORE broadcasting: a failed Council is worth stopping early.
        require(address(governor.timelock()) == address(timelock), "governor points at another timelock");
        require(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "governor cannot propose");
        require(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), "nobody can execute");
        bytes32 adminRole = timelock.DEFAULT_ADMIN_ROLE();

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        address[] memory owners = new address[](1);
        owners[0] = townAdmin; // the admin adds student signers through the multisig itself
        TownTreasury treasury = new TownTreasury(owners, threshold, TrustvillePassport(passportAddr));
        vm.stopBroadcast();

        _record("TownTimelock", address(timelock));
        _record("TownGovernor", address(governor));
        _record("TownTreasury", address(treasury));

        console.log("");
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

        // Checked last so the addresses above are written either way, but still fatal: a
        // Timelock with a live admin is a treasury one key can drain.
        require(!timelock.hasRole(adminRole, deployer), "deployer is STILL admin of the timelock - renounce first");
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
