// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CropInsurance} from "../src/CropInsurance.sol";
import {RainOracle} from "../src/RainOracle.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Phase D4b — the Insurer (module 14).
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployInsurer.s.sol --rpc-url didlab --account didlab-deployer \
///     --sender <deployer> --legacy --slow --gas-estimate-multiplier 105 --broadcast
///
/// Defaults suit a lab: a 10-minute "day", 3 of N reporters, under 5mm is a drought, and a
/// 10% premium. Override with PERIOD_SECONDS / QUORUM / TRIGGER_MM / PREMIUM_BPS.
///
/// Two contracts, no wiring between them that can half-finish: the insurer is constructed
/// with the oracle's address and never changes it. Everything else is admin-signed and
/// printed below.
contract DeployInsurer is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        uint32 periodSeconds = uint32(vm.envOr("PERIOD_SECONDS", uint256(600)));
        uint32 quorum = uint32(vm.envOr("QUORUM", uint256(3)));
        uint32 triggerMm = uint32(vm.envOr("TRIGGER_MM", uint256(5)));
        uint16 premiumBps = uint16(vm.envOr("PREMIUM_BPS", uint256(1000)));

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(passportAddr != address(0) && tokenAddr != address(0), "D1 not deployed");

        vm.startBroadcast();
        RainOracle oracle = new RainOracle(townAdmin, periodSeconds, quorum);
        CropInsurance insurer = new CropInsurance(
            IERC20(tokenAddr),
            oracle,
            townAdmin,
            triggerMm,
            premiumBps,
            TrustvillePassport(passportAddr)
        );
        vm.stopBroadcast();

        _record("RainOracle", address(oracle));
        _record("CropInsurance", address(insurer));

        console.log("");
        console.log("Period (s) / quorum / trigger mm / premium bps:");
        console.log(periodSeconds, quorum, triggerMm, premiumBps);
        console.log("");
        console.log("NEXT, as the ADMIN. 1) let the insurer stamp passports:");
        console.log(
            string.concat(
                "cast send ",
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(insurer)),
                " --rpc-url https://eth.didlab.org --legacy --interactive"
            )
        );
        console.log("");
        console.log("2) appoint each reporter (REPORTER_ROLE), once per address:");
        console.log(
            string.concat(
                "cast send ",
                vm.toString(address(oracle)),
                ' "grantRole(bytes32,address)" ',
                vm.toString(keccak256("REPORTER_ROLE")),
                " <reporter address> --rpc-url https://eth.didlab.org --legacy --interactive"
            )
        );
        console.log("");
        console.log("3) capitalise the pool, or the insurer can sell nothing:");
        console.log(
            string.concat(
                "cast send ",
                vm.toString(tokenAddr),
                ' "approve(address,uint256)" ',
                vm.toString(address(insurer)),
                " 1000000000000000000000 --rpc-url https://eth.didlab.org --legacy --interactive"
            )
        );
        console.log(
            string.concat(
                "cast send ",
                vm.toString(address(insurer)),
                ' "fund(uint256)" 1000000000000000000000',
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
