// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TownGovernor} from "../src/TownGovernor.sol";
import {TownTimelock} from "../src/TownTimelock.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Replace the Council's Governor and Timelock, and keep everything else.
///
///   cd contracts
///   DEPLOYER=$(cast wallet address --account didlab-deployer)
///   forge script script/DeployGovernance.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender "$DEPLOYER" --legacy --slow --broadcast
///
/// Why a pair and not just a Governor: the Timelock only takes orders from a proposer it
/// has been told about, and after deployment nobody holds its admin role (that is the
/// point of it). So a new Governor cannot be introduced to the old Timelock except by a
/// proposal the old Governor passes. A fresh pair is one script and no vote.
///
/// The VoteToken stays, so every resident's wrapped vTVD and delegation carry over. The
/// multisig Treasury (module 11) is a separate contract and is untouched.
///
/// Afterwards, as the ADMIN, grant the new Governor STAMPER_ROLE on the passport — on the
/// site's Admin page, so the key never leaves MetaMask — or it will count votes and stamp
/// nobody. The old Timelock keeps any TVD it held; send the new one whatever the Council
/// should be able to spend.
///
/// If a run stops part-way — the Timelock deployed but the Governor refused, say — rerun
/// with TIMELOCK=<that timelock> to reuse it rather than leave an orphan. It must still be
/// waiting for its wiring (the deployer still holds its admin role).
///
/// Two things learned on DIDLab (2026-09-30):
///   - The Governor costs ~4.25M gas to deploy, close to DIDLab's block gas limit, so keep
///     --gas-estimate-multiplier at 100–102 here. At 115 the node refused the transaction.
///   - forge writes deployments/*.json while SIMULATING, before anything is sent. When a
///     broadcast fails, the file names contracts that were never deployed. Check every new
///     address with `cast code <addr> --rpc-url didlab` before trusting the file.
///
/// Timings default to a lab session: 1 min voting delay, 10 min voting, 2 min timelock.
/// Override with VOTING_DELAY / VOTING_PERIOD / TIMELOCK_DELAY (seconds).
contract DeployGovernance is Script {
    function run() external {
        uint48 votingDelay = uint48(vm.envOr("VOTING_DELAY", uint256(60)));
        uint32 votingPeriod = uint32(vm.envOr("VOTING_PERIOD", uint256(600)));
        uint256 timelockDelay = vm.envOr("TIMELOCK_DELAY", uint256(120));

        string memory path = string.concat(
            vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json"
        );
        string memory json = vm.readFile(path);
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address voteTokenAddr = vm.parseJsonAddress(json, ".contracts.VoteToken");
        require(
            passportAddr != address(0) && voteTokenAddr != address(0), "no passport or VoteToken"
        );

        address existing = vm.envOr("TIMELOCK", address(0));

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        TownTimelock timelock;
        if (existing == address(0)) {
            address[] memory none = new address[](0);
            timelock = new TownTimelock(timelockDelay, none, none, deployer);
        } else {
            timelock = TownTimelock(payable(existing));
            require(
                timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer),
                "TIMELOCK is already wired (or not ours): deploy a fresh pair instead"
            );
        }
        TownGovernor governor = new TownGovernor(
            IVotes(voteTokenAddr),
            timelock,
            votingDelay,
            votingPeriod,
            0,
            TrustvillePassport(passportAddr)
        );

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));
        // Explicit gas: renouncing clears a storage slot, and the refund makes forge's
        // estimate (gas used, after the refund) too small for the call to actually run.
        // With the low multiplier the Governor needs, this line reverted on its own.
        timelock.renounceRole{gas: 100_000}(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopBroadcast();

        require(
            !timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer),
            "timelock still has an admin"
        );
        require(
            timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), "governor cannot propose"
        );

        _record("TownTimelock", address(timelock));
        _record("TownGovernor", address(governor));

        console.log("");
        console.log("NEXT, as the ADMIN, on the site's Admin page:");
        console.log("  TrustvillePassport - grant STAMPER_ROLE to", address(governor));
        console.log("Then: npm run sync-abi, build, commit dist/, deploy.");
    }

    function _record(string memory name, address addr) internal {
        string memory path = string.concat(
            vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json"
        );
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
