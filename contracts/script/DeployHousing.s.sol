// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PropertyDeeds} from "../src/PropertyDeeds.sol";
import {RentEscrow} from "../src/RentEscrow.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";
import {VoteToken} from "../src/VoteToken.sol";

/// Phase D3a — Housing (modules 9-10) plus the voting wrapper the Council will need.
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress
///   forge script script/DeployHousing.s.sol --rpc-url didlab --account didlab-deployer \
///     --legacy --broadcast
///
/// Then grant STAMPER_ROLE with the ADMIN key (see the printed cast commands).
contract DeployHousing is Script {
    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        string memory json = vm.readFile(path);

        address registryAddr = vm.parseJsonAddress(json, ".contracts.ResidentRegistry");
        address passportAddr = vm.parseJsonAddress(json, ".contracts.TrustvillePassport");
        address tokenAddr = vm.parseJsonAddress(json, ".contracts.TownToken");
        require(registryAddr != address(0) && passportAddr != address(0) && tokenAddr != address(0), "D1 not deployed");
        require(townAdmin != address(0), "TOWN_ADMIN not set");

        vm.startBroadcast();
        PropertyDeeds deeds =
            new PropertyDeeds(townAdmin, ResidentRegistry(registryAddr), TrustvillePassport(passportAddr));
        RentEscrow leases = new RentEscrow(
            townAdmin, IERC20(tokenAddr), IERC721(address(deeds)), TrustvillePassport(passportAddr)
        );
        VoteToken votes = new VoteToken(IERC20(tokenAddr));
        vm.stopBroadcast();

        _record("PropertyDeeds", address(deeds));
        _record("RentEscrow", address(leases));
        _record("VoteToken", address(votes));

        console.log("");
        console.log("Deeds certifier and rent arbiter: the town admin", townAdmin);
        console.log("NEXT, as the ADMIN (the deployer holds no roles):");
        console.log(
            string.concat(
                'cast send ',
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(deeds)),
                " --rpc-url didlab --legacy --interactive"
            )
        );
        console.log(
            string.concat(
                'cast send ',
                vm.toString(passportAddr),
                ' "grantRole(bytes32,address)" 0x57980102bbeb8858f40747983e69e30ef38ad79e5d2161e7bb937ea9df8528c8 ',
                vm.toString(address(leases)),
                " --rpc-url didlab --legacy --interactive"
            )
        );
        console.log("VoteToken needs no roles: it only wraps TVD.");
    }

    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
