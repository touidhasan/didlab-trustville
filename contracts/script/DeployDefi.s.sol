// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GrainLoans} from "../src/GrainLoans.sol";
import {GrainToken} from "../src/GrainToken.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownSwap} from "../src/TownSwap.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D4c — the Bank stop grows up (module 15).
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployDefi.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender <deployer> --legacy --slow --gas-estimate-multiplier 105 --broadcast
///
/// Defaults: harvest cooldown 10 minutes, borrowing interest 10% a year.
/// Override with HARVEST_COOLDOWN / RATE_BPS.
///
/// GrainLoans prices collateral from the AMM spot price ON PURPOSE. It is the module's
/// exercise, and the repository says so loudly. Deploy it on DIDLab, never anywhere the
/// tokens are worth something.
contract DeployDefi is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        uint64 cooldown = uint64(vm.envOr("HARVEST_COOLDOWN", uint256(600)));
        uint256 rateBps = vm.envOr("RATE_BPS", uint256(1000));

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        address registryAddr = vm.parseJsonAddress(json, ".contracts.ResidentRegistry");
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(
            registryAddr != address(0) && passportAddr != address(0) && tokenAddr != address(0),
            "D1 not deployed"
        );

        vm.startBroadcast();
        GrainToken grain = new GrainToken(townAdmin, ResidentRegistry(registryAddr), cooldown);
        TownSwap swap = new TownSwap(
            IERC20(tokenAddr), IERC20(address(grain)), TrustvillePassport(passportAddr)
        );
        GrainLoans loans = new GrainLoans(
            IERC20(tokenAddr),
            IERC20(address(grain)),
            swap,
            townAdmin,
            rateBps,
            TrustvillePassport(passportAddr)
        );
        vm.stopBroadcast();

        _record("GrainToken", address(grain));
        _record("TownSwap", address(swap));
        _record("GrainLoans", address(loans));

        console.log("");
        console.log("Harvest cooldown (s) / borrow rate (bps):", cooldown, rateBps);
        console.log("");
        console.log("NEXT, as the ADMIN. Let both contracts stamp passports:");
        _grant(passportAddr, address(swap));
        _grant(passportAddr, address(loans));
        console.log("");
        console.log("Then seed the market, from any resident account that has harvested:");
        console.log("  1. harvest() on GrainToken until you hold enough GRAIN");
        console.log("  2. approve TownSwap for both tokens");
        console.log("  3. addLiquidity(1000e18, 1000e18, 0) -- this sets the opening price");
        console.log("  4. approve GrainLoans for TVD, then supply(500e18) so there is something to borrow");
        console.log("");
        console.log("WARNING: GrainLoans prices collateral from the AMM spot price, which a");
        console.log("borrower can move inside one transaction. That is deliberate. See");
        console.log("docs/modules/15-defi.md before anyone treats this as a template.");
    }

    function _grant(address passportAddr, address who) internal pure {
        console.log(
            string.concat(
                "cast send ",
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(who),
                " --rpc-url https://eth.didlab.org --legacy --interactive"
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
