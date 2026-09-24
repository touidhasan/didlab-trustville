// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Grants STAMPER_ROLE on the Passport to the two College contracts.
/// MUST be signed by the TOWN ADMIN key — the deployer holds no roles.
///
/// See the calls without signing anything:
///   forge script script/GrantCollegeRoles.s.sol --rpc-url didlab --legacy
///
/// Sign them with an admin keystore:
///   forge script script/GrantCollegeRoles.s.sol --rpc-url didlab --legacy --broadcast \
///     --account <admin-keystore>
///
/// Or, if the admin key lives in MetaMask, paste the two `cast send` lines this prints
/// and answer the prompt with the exported key.
contract GrantCollegeRoles is Script {
    function run() external {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        TrustvillePassport passport =
            TrustvillePassport(vm.parseJsonAddress(json, ".contracts.TrustvillePassport"));
        address certs = vm.parseJsonAddress(json, ".contracts.CertificateRegistry");
        address tickets = vm.parseJsonAddress(json, ".contracts.EventTickets");
        bytes32 role = passport.STAMPER_ROLE();

        console.log("Copy-paste, as the admin (it will prompt for the key):");
        console.log("");
        _printCast(address(passport), role, certs);
        _printCast(address(passport), role, tickets);
        console.log("");

        vm.startBroadcast();
        if (!passport.hasRole(role, certs)) passport.grantRole(role, certs);
        if (!passport.hasRole(role, tickets)) passport.grantRole(role, tickets);
        vm.stopBroadcast();

        require(passport.hasRole(role, certs), "certificates cannot stamp");
        require(passport.hasRole(role, tickets), "tickets cannot stamp");
        console.log("Both College contracts can now stamp passports.");
    }

    function _printCast(address passport, bytes32 role, address target) internal pure {
        console.log(
            string.concat(
                "cast send ",
                vm.toString(passport),
                ' "grantRole(bytes32,address)" ',
                vm.toString(role),
                " ",
                vm.toString(target),
                " --rpc-url didlab --legacy --interactive"
            )
        );
    }
}
