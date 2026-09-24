// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";
import {EventTickets} from "../src/EventTickets.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D2b — the College (modules 7-8). Run with the DEPLOYER key:
///
///   cd contracts
///   forge script script/DeployCollege.s.sol --rpc-url didlab --account didlab-deployer \
///     --legacy --broadcast
///
/// Then grant STAMPER_ROLE with the ADMIN key: script/GrantCollegeRoles.s.sol.
contract DeployCollege is Script {
    function run() external {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        address registryAddr = vm.parseJsonAddress(json, ".contracts.ResidentRegistry");
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(registryAddr != address(0) && passportAddr != address(0) && tokenAddr != address(0), "D1 not deployed");

        vm.startBroadcast();
        CertificateRegistry certs =
            new CertificateRegistry(ResidentRegistry(registryAddr), TrustvillePassport(passportAddr));
        EventTickets tickets = new EventTickets(
            IERC20(tokenAddr), ResidentRegistry(registryAddr), TrustvillePassport(passportAddr)
        );
        vm.stopBroadcast();

        _record("CertificateRegistry", address(certs));
        _record("EventTickets", address(tickets));

        console.log("");
        console.log("NEXT, signed by the ADMIN key (the deployer cannot do this):");
        console.log("  forge script script/GrantCollegeRoles.s.sol --rpc-url didlab --legacy --broadcast \\");
        console.log("    --account <admin-keystore>");
        console.log("Until then the College runs but awards no passport stamps.");
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
