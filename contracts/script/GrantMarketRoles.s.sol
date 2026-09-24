// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Grants STAMPER_ROLE on the Passport to the three Market contracts.
/// MUST be signed by the TOWN ADMIN key — this is the one thing the deployer cannot do,
/// which is the whole point of handing privileges over at deployment.
///
///   cd contracts
///   forge script script/GrantMarketRoles.s.sol --rpc-url didlab --legacy --broadcast \
///     --account <admin-keystore>
///
/// If the admin key lives in MetaMask and you would rather not export it, do the same
/// three calls by hand from the explorer or with `cast send --interactive`; the script
/// prints them.
contract GrantMarketRoles is Script {
    function run() external {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        TrustvillePassport passport =
            TrustvillePassport(vm.parseJsonAddress(json, ".contracts.TrustvillePassport"));
        address products = vm.parseJsonAddress(json, ".contracts.ProductRegistry");
        address escrow = vm.parseJsonAddress(json, ".contracts.TownEscrow");
        address auction = vm.parseJsonAddress(json, ".contracts.SealedAuction");

        bytes32 role = passport.STAMPER_ROLE();

        console.log("Passport:", address(passport));
        console.log("If signing by hand, send these three calls as the admin:");
        console.log("  grantRole(STAMPER_ROLE, %s)", products);
        console.log("  grantRole(STAMPER_ROLE, %s)", escrow);
        console.log("  grantRole(STAMPER_ROLE, %s)", auction);

        vm.startBroadcast();
        if (!passport.hasRole(role, products)) passport.grantRole(role, products);
        if (!passport.hasRole(role, escrow)) passport.grantRole(role, escrow);
        if (!passport.hasRole(role, auction)) passport.grantRole(role, auction);
        vm.stopBroadcast();

        require(passport.hasRole(role, products), "products cannot stamp");
        require(passport.hasRole(role, escrow), "escrow cannot stamp");
        require(passport.hasRole(role, auction), "auction cannot stamp");
        console.log("All three Market contracts can now stamp passports.");
    }
}
