// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GrainLoans} from "../src/GrainLoans.sol";
import {TownSwap} from "../src/TownSwap.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Replace GrainLoans on its own, keeping GRAIN and the swap (and so every harvest and
/// every liquidity position).
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   DEPLOYER=$(cast wallet address --account didlab-deployer)
///   forge script script/DeployLoans.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender "$DEPLOYER" --legacy --slow --broadcast
///
/// Afterwards, as the ADMIN, grant the new GrainLoans STAMPER_ROLE on the passport (Admin
/// page), and supply some TVD to it so there is something to borrow. Whatever was supplied
/// to the old one stays there, withdrawable by whoever supplied it.
///
/// Default borrowing rate 10% a year; override with RATE_BPS.
contract DeployLoans is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        uint256 rateBps = vm.envOr("RATE_BPS", uint256(1000));

        string memory path = string.concat(
            vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json"
        );
        string memory json = vm.readFile(path);
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        address grainAddr = vm.parseJsonAddress(json, ".contracts.GrainToken");
        address swapAddr = vm.parseJsonAddress(json, ".contracts.TownSwap");
        require(swapAddr != address(0) && grainAddr != address(0), "the Exchange is not deployed");

        vm.startBroadcast();
        GrainLoans loans = new GrainLoans(
            IERC20(tokenAddr),
            IERC20(grainAddr),
            TownSwap(swapAddr),
            townAdmin,
            rateBps,
            TrustvillePassport(passportAddr)
        );
        vm.stopBroadcast();

        vm.writeJson(vm.toString(address(loans)), path, ".contracts.GrainLoans");
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log("GrainLoans", address(loans));
        console.log("");
        console.log("NEXT, as the ADMIN, on the site's Admin page:");
        console.log("  TrustvillePassport - grant STAMPER_ROLE to", address(loans));
        console.log("Then supply TVD to it, npm run sync-abi, build, commit dist/, deploy.");
    }
}
