// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProductRegistry} from "../src/ProductRegistry.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {SealedAuction} from "../src/SealedAuction.sol";
import {TownEscrow} from "../src/TownEscrow.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Phase D2a — the Market (modules 4-6). Run with the DEPLOYER key:
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployMarket.s.sol --rpc-url didlab --account didlab-deployer \
///     --legacy --broadcast
///
/// The deployer holds no roles on the D1 contracts (by design), so it CANNOT grant the new
/// contracts permission to stamp passports. That is a separate, admin-signed step:
/// script/GrantMarketRoles.s.sol. Until it runs, the Market works but awards no stamps.
contract DeployMarket is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        address registryAddr = vm.parseJsonAddress(json, ".contracts.ResidentRegistry");
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(registryAddr != address(0) && passportAddr != address(0) && tokenAddr != address(0), "D1 not deployed");

        vm.startBroadcast();

        ProductRegistry products =
            new ProductRegistry(ResidentRegistry(registryAddr), TrustvillePassport(passportAddr));
        TownEscrow escrow =
            new TownEscrow(townAdmin, IERC20(tokenAddr), TrustvillePassport(passportAddr));
        SealedAuction auction =
            new SealedAuction(IERC20(tokenAddr), TrustvillePassport(passportAddr));

        vm.stopBroadcast();

        _record("ProductRegistry", address(products));
        _record("TownEscrow", address(escrow));
        _record("SealedAuction", address(auction));

        console.log("");
        console.log("Deployed. Escrow arbiter is the town admin:", townAdmin);
        console.log("NEXT, signed by the ADMIN key (the deployer cannot do this):");
        console.log("  forge script script/GrantMarketRoles.s.sol --rpc-url didlab --legacy --broadcast \\");
        console.log("    --account <admin-keystore>   # or --ledger / --trezor");
        console.log("Until then the Market runs but awards no passport stamps.");
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
