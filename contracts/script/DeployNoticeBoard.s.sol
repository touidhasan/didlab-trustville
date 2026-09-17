// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TownNoticeBoard} from "../src/TownNoticeBoard.sol";

/// Deploy to the DIDLab chain with your own key (never commit it):
///
///   cd contracts
///   forge script script/DeployNoticeBoard.s.sol --rpc-url didlab --broadcast --interactive 1
///
/// Then copy the printed address into deployments/252501.json under
/// "contracts": { "TownNoticeBoard": "0x..." }
contract DeployNoticeBoard is Script {
    function run() external returns (TownNoticeBoard board) {
        vm.startBroadcast();
        board = new TownNoticeBoard();
        vm.stopBroadcast();
        console.log("TownNoticeBoard deployed at", address(board));
    }
}
