// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TownTreasury} from "../src/TownTreasury.sol";

/// Move every privilege from one admin address to another, then give up the old one.
///
///   cd contracts
///   export OLD_ADMIN=0x...          # the key being retired
///   export NEW_ADMIN=0x...          # a fresh account, used for nothing else
///   # 1. grant only, and check the result before giving anything up:
///   SKIP_RENOUNCE=1 forge script script/RotateAdmin.s.sol --rpc-url didlab \
///     --legacy --slow --broadcast --interactive
///   # 2. when the checks pass, the same command without SKIP_RENOUNCE
///
/// Signed by the OLD admin — it is the only account that can hand these over.
///
/// Note there is no `--gas-estimate-multiplier` here. This script deploys nothing, so
/// Foundry's default 130% padding applies, which matters: `renounceRole` clears a storage
/// slot and earns a refund that the estimator nets out. At 105% it runs out of gas. That
/// is exactly how the D3b Council deployment broke.
///
/// Deliberately in two phases. Granting is additive and safe to repeat; renouncing is
/// irreversible. Running phase one, looking at the output, and only then running phase two
/// means a mistake in the address costs a transaction instead of the town.
contract RotateAdmin is Script {
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

    struct Target {
        string name;
        bytes32 role;
        string label;
    }

    Target[] private _targets;
    string private _json;

    function run() external {
        address oldAdmin = vm.envAddress("OLD_ADMIN");
        address newAdmin = vm.envAddress("NEW_ADMIN");
        bool skipRenounce = vm.envOr("SKIP_RENOUNCE", uint256(0)) == 1;
        require(oldAdmin != newAdmin, "the new admin must be a different account");
        require(newAdmin != address(0), "NEW_ADMIN is not set");

        string memory path =
            string.concat(vm.projectRoot(), "/../deployments/", vm.toString(block.chainid), ".json");
        _json = vm.readFile(path);

        _load();

        console.log("Rotating from", oldAdmin);
        console.log("            to", newAdmin);
        console.log("");

        /* ------------------------------------------------------- phase 1: grant */
        vm.startBroadcast();
        uint256 granted;
        for (uint256 i; i < _targets.length; i++) {
            address c = _addr(_targets[i].name);
            if (c == address(0)) continue;
            IAccessControl ac = IAccessControl(c);
            if (!ac.hasRole(_targets[i].role, oldAdmin)) continue; // nothing to hand over
            if (ac.hasRole(_targets[i].role, newAdmin)) continue; // already done
            ac.grantRole(_targets[i].role, newAdmin);
            granted++;
        }
        vm.stopBroadcast();
        console.log("granted:", granted);

        /* --------------------------------------- verify before giving anything up */
        uint256 held;
        for (uint256 i; i < _targets.length; i++) {
            address c = _addr(_targets[i].name);
            if (c == address(0)) continue;
            IAccessControl ac = IAccessControl(c);
            if (!ac.hasRole(_targets[i].role, oldAdmin)) continue;
            require(
                ac.hasRole(_targets[i].role, newAdmin),
                string.concat("new admin is missing ", _targets[i].label)
            );
            held++;
        }
        console.log("verified on the new admin:", held);

        if (skipRenounce) {
            console.log("");
            console.log("SKIP_RENOUNCE set: the old admin still holds everything.");
            console.log("Check the list above, then run again without SKIP_RENOUNCE.");
            _treasuryNote(oldAdmin, newAdmin);
            return;
        }

        /* ---------------------------------------------------- phase 2: renounce */
        vm.startBroadcast();
        uint256 dropped;
        for (uint256 i; i < _targets.length; i++) {
            address c = _addr(_targets[i].name);
            if (c == address(0)) continue;
            IAccessControl ac = IAccessControl(c);
            if (!ac.hasRole(_targets[i].role, oldAdmin)) continue;
            ac.renounceRole(_targets[i].role, oldAdmin);
            dropped++;
        }
        vm.stopBroadcast();
        console.log("renounced by the old admin:", dropped);

        /* --------------------------------------------------------------- assert */
        for (uint256 i; i < _targets.length; i++) {
            address c = _addr(_targets[i].name);
            if (c == address(0)) continue;
            require(
                !IAccessControl(c).hasRole(_targets[i].role, oldAdmin),
                string.concat("old admin STILL holds ", _targets[i].label)
            );
        }
        console.log("");
        console.log("Done. The old key holds no role on any Trustville contract.");
        _treasuryNote(oldAdmin, newAdmin);
    }

    /// The multisig is the one thing this script cannot rotate. Owner changes go through
    /// the multisig itself by design — no back door, which is the property module 11
    /// exists to demonstrate. So it is two proposals, made by the old admin while it is
    /// still an owner.
    function _treasuryNote(address oldAdmin, address newAdmin) internal view {
        address treasury = _addr("TownTreasury");
        if (treasury == address(0)) return;
        if (!TownTreasury(payable(treasury)).isOwner(oldAdmin)) return;

        console.log("");
        console.log("STILL TO DO - the treasury multisig, which cannot be rotated from here:");
        console.log(
            string.concat(
                "cast send ",
                vm.toString(treasury),
                ' "propose(address,uint256,bytes,string)" ',
                vm.toString(treasury),
                " 0 ",
                vm.toString(abi.encodeWithSignature("addOwner(address)", newAdmin)),
                ' "rotate: add the new admin" --rpc-url https://eth.didlab.org --legacy --interactive'
            )
        );
        console.log('then: cast send <treasury> "execute(uint256)" <the id it printed> ... ');
        console.log("and repeat with:");
        console.log(
            string.concat(
                "  data = ", vm.toString(abi.encodeWithSignature("removeOwner(address)", oldAdmin))
            )
        );
        console.log("Add the new owner and confirm it BEFORE removing the old one.");
    }

    /* ------------------------------------------------------------------ plumbing */

    function _load() private {
        bytes32 REGISTRAR = keccak256("REGISTRAR_ROLE");
        bytes32 ARBITER = keccak256("ARBITER_ROLE");
        bytes32 CERTIFIER = keccak256("CERTIFIER_ROLE");

        _add("ResidentRegistry", DEFAULT_ADMIN_ROLE, "ResidentRegistry admin");
        _add("ResidentRegistry", REGISTRAR, "ResidentRegistry registrar");
        _add("TrustvillePassport", DEFAULT_ADMIN_ROLE, "Passport admin");
        _add("TownToken", DEFAULT_ADMIN_ROLE, "TownToken admin");
        _add("TownBank", DEFAULT_ADMIN_ROLE, "TownBank admin");
        _add("TownEscrow", DEFAULT_ADMIN_ROLE, "TownEscrow admin");
        _add("TownEscrow", ARBITER, "TownEscrow arbiter");
        _add("PropertyDeeds", DEFAULT_ADMIN_ROLE, "PropertyDeeds admin");
        _add("PropertyDeeds", CERTIFIER, "PropertyDeeds certifier");
        _add("RentEscrow", DEFAULT_ADMIN_ROLE, "RentEscrow admin");
        _add("RentEscrow", ARBITER, "RentEscrow arbiter");
        _add("TownCharity", DEFAULT_ADMIN_ROLE, "TownCharity admin");
        _add("TownCharity", ARBITER, "TownCharity arbiter");
        _add("RainOracle", DEFAULT_ADMIN_ROLE, "RainOracle admin");
        _add("CropInsurance", DEFAULT_ADMIN_ROLE, "CropInsurance admin");
        _add("GrainToken", DEFAULT_ADMIN_ROLE, "GrainToken admin");
        _add("GrainLoans", DEFAULT_ADMIN_ROLE, "GrainLoans admin");
    }

    function _add(string memory name, bytes32 role, string memory label) private {
        _targets.push(Target({name: name, role: role, label: label}));
    }

    /// Missing from the deployments file simply means not deployed on this chain yet.
    function _addr(string memory name) private view returns (address) {
        string memory key = string.concat(".contracts.", name);
        if (!vm.keyExistsJson(_json, key)) return address(0);
        return vm.parseJsonAddress(_json, key);
    }
}
