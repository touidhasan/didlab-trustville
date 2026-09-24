// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TownCharity} from "../src/TownCharity.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D4a — the Charity (module 13).
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployCharity.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender <deployer> --legacy --slow --gas-estimate-multiplier 105 --broadcast
///
/// One contract, so nothing here can strand a half-wired deployment. The admin-signed
/// stamping grant is printed at the end — until it runs, pledging works but awards no
/// passport stamp.
contract DeployCharity is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(passportAddr != address(0) && tokenAddr != address(0), "D1 not deployed");

        vm.startBroadcast();
        TownCharity charity =
            new TownCharity(IERC20(tokenAddr), townAdmin, TrustvillePassport(passportAddr));
        vm.stopBroadcast();

        _record("TownCharity", address(charity));

        console.log("");
        console.log("Arbiter (approves milestones, never holds the money):", townAdmin);
        console.log("NEXT, as the ADMIN:");
        console.log(
            string.concat(
                "cast send ",
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(charity)),
                " --rpc-url https://eth.didlab.org --legacy --interactive"
            )
        );
        console.log("Then verify:");
        console.log(
            string.concat(
                "cast call ",
                vm.toString(passportAddr),
                ' "hasRole(bytes32,address)(bool)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(charity)),
                " --rpc-url https://eth.didlab.org"
            )
        );
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
