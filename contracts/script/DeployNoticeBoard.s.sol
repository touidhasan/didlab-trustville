// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TownNoticeBoard} from "../src/TownNoticeBoard.sol";

/// Deploy to the DIDLab chain with your own key (never commit it):
///
///   cd contracts
///   forge script script/DeployNoticeBoard.s.sol --rpc-url didlab --broadcast --interactive 1
///
/// On success the script writes the address into deployments/<chainid>.json itself,
/// so there is nothing to edit by hand. Then: npm run build && git commit && push.
contract DeployNoticeBoard is Script {
    function run() external returns (TownNoticeBoard board) {
        vm.startBroadcast();
        board = new TownNoticeBoard();
        vm.stopBroadcast();

        _record("TownNoticeBoard", address(board));

        console.log("TownNoticeBoard deployed at", address(board));
        console.log("Next: npm run build, then commit dist/ and deployments/, then redeploy in cPanel.");
    }

    /// Writes one address into deployments/<chainid>.json, keeping every other entry.
    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");

        if (!vm.exists(path)) {
            vm.writeFile(
                path,
                string.concat(
                    '{\n  "chainId": ',
                    vm.toString(block.chainid),
                    ',\n  "network": "DIDLab",\n  "updated": null,\n  "contracts": {}\n}\n'
                )
            );
        }

        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log("Recorded in", path);
    }
}
