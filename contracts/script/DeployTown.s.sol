// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Deploys phase D1 and hands every privilege to the TOWN_ADMIN key.
///
///   cd contracts
///   export TOWN_ADMIN=0xYourAdminAddress          # the KEYSTORE key, not the deployer
///   forge script script/DeployTown.s.sol --rpc-url didlab --broadcast --account didlab-deployer
///
/// The deployer is admin only while this script runs: it wires the contracts together,
/// grants DEFAULT_ADMIN_ROLE to TOWN_ADMIN, then renounces everything it holds.
/// If the handover fails, the script reverts — a half-owned town never reaches the chain.
contract DeployTown is Script {
    bytes32 constant ADMIN = 0x00; // DEFAULT_ADMIN_ROLE

    function run() external {
        address townAdmin = vm.envAddress("TOWN_ADMIN");
        uint256 grant = vm.envOr("WELCOME_GRANT", uint256(100 ether));
        uint256 maxSupply = vm.envOr("TVD_MAX_SUPPLY", uint256(10_000_000 ether));

        vm.startBroadcast();
        address deployer = msg.sender;
        require(townAdmin != address(0), "TOWN_ADMIN not set");
        require(townAdmin != deployer, "TOWN_ADMIN must differ from the deployer key");

        // 1. Deploy with the deployer as temporary admin, so wiring needs no second signer.
        ResidentRegistry registry = new ResidentRegistry(deployer);
        TrustvillePassport passport = new TrustvillePassport(deployer, registry);
        TownToken token = new TownToken(deployer, maxSupply);
        TownBank bank = new TownBank(deployer, registry, token, passport, grant);

        // 2. Roles go to CONTRACTS, never to people.
        token.grantRole(token.MINTER_ROLE(), address(bank));
        passport.grantRole(passport.STAMPER_ROLE(), address(bank));

        // 3. Hand the town to the admin key — including every non-default role the
        //    deployer holds, or the admin ends up unable to run the town it owns.
        registry.grantRole(registry.REGISTRAR_ROLE(), townAdmin);
        _handOver(address(registry), deployer, townAdmin);
        _handOver(address(passport), deployer, townAdmin);
        _handOver(address(token), deployer, townAdmin);
        _handOver(address(bank), deployer, townAdmin);
        registry.renounceRole(registry.REGISTRAR_ROLE(), deployer);

        vm.stopBroadcast();

        // 4. Prove the handover worked, or fail the deployment.
        require(!registry.hasRole(ADMIN, deployer), "deployer still admin: registry");
        require(!passport.hasRole(ADMIN, deployer), "deployer still admin: passport");
        require(!token.hasRole(ADMIN, deployer), "deployer still admin: token");
        require(!bank.hasRole(ADMIN, deployer), "deployer still admin: bank");
        require(!registry.hasRole(registry.REGISTRAR_ROLE(), deployer), "deployer still registrar");
        require(token.hasRole(token.MINTER_ROLE(), address(bank)), "bank cannot mint");
        require(registry.hasRole(ADMIN, townAdmin), "admin key has no control");
        require(registry.hasRole(registry.REGISTRAR_ROLE(), townAdmin), "admin cannot register");

        _record("ResidentRegistry", address(registry));
        _record("TrustvillePassport", address(passport));
        _record("TownToken", address(token));
        _record("TownBank", address(bank));

        console.log("Town admin:", townAdmin);
        console.log("Deployer now holds no roles.");
        console.log("Next: npm run build, commit dist/ + deployments/, push, redeploy in cPanel.");
    }

    function _handOver(address target, address deployer, address townAdmin) internal {
        IAccessControl(target).grantRole(ADMIN, townAdmin);
        IAccessControl(target).renounceRole(ADMIN, deployer);
    }

    /// Writes one address into deployments/<chainid>.json, keeping every other entry.
    function _record(string memory name, address addr) internal {
        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        if (!vm.exists(path)) {
            vm.writeFile(
                path,
                string.concat(
                    '{\n  "chainId": ',
                    vm.toString(block.chainid),
                    ',\n  "network": "DIDLab",\n  "updated": null,\n  "contracts": {}\n}\n'
                )
            );
        }
        vm.writeJson(vm.toString(addr), path, string.concat(".contracts.", name));
        vm.writeJson(vm.toString(block.timestamp), path, ".updated");
        console.log(name, addr);
    }
}
