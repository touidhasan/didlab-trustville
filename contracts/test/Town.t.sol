// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

contract TownTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant GRANT = 100 ether;

    function setUp() public {
        // Mirrors script/DeployTown.s.sol exactly, including the handover.
        vm.startPrank(deployer);
        registry = new ResidentRegistry(deployer);
        passport = new TrustvillePassport(deployer, registry);
        token = new TownToken(deployer, 10_000_000 ether);
        bank = new TownBank(deployer, registry, token, passport, GRANT);

        token.grantRole(token.MINTER_ROLE(), address(bank));
        passport.grantRole(passport.STAMPER_ROLE(), address(bank));

        registry.grantRole(registry.REGISTRAR_ROLE(), townAdmin);
        _handOver(address(registry));
        _handOver(address(passport));
        _handOver(address(token));
        _handOver(address(bank));
        registry.renounceRole(registry.REGISTRAR_ROLE(), deployer);
        vm.stopPrank();
    }

    function _handOver(address target) internal {
        IAccessControl(target).grantRole(ADMIN, townAdmin);
        IAccessControl(target).renounceRole(ADMIN, deployer);
    }

    function _becomeResident(address who) internal {
        vm.prank(who);
        registry.register(keccak256(abi.encodePacked("credential:", who)));
    }

    /* ---------------------------------------------------------- keys and roles */

    function test_DeployerHoldsNothingAfterHandover() public view {
        assertFalse(registry.hasRole(ADMIN, deployer));
        assertFalse(passport.hasRole(ADMIN, deployer));
        assertFalse(token.hasRole(ADMIN, deployer));
        assertFalse(bank.hasRole(ADMIN, deployer));
        assertFalse(registry.hasRole(registry.REGISTRAR_ROLE(), deployer));
        assertFalse(token.hasRole(token.MINTER_ROLE(), deployer));
        assertFalse(passport.hasRole(passport.STAMPER_ROLE(), deployer));
    }

    function test_AdminKeyControlsEverything() public view {
        assertTrue(registry.hasRole(ADMIN, townAdmin));
        assertTrue(passport.hasRole(ADMIN, townAdmin));
        assertTrue(token.hasRole(ADMIN, townAdmin));
        assertTrue(bank.hasRole(ADMIN, townAdmin));
    }

    function test_OnlyTheBankCanMint() public {
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(bank)));
        // Not even the admin can print money directly.
        vm.prank(townAdmin);
        vm.expectRevert();
        token.mint(townAdmin, 1 ether);
    }

    function test_AdminCanRotateItsOwnKey() public {
        address newAdmin = makeAddr("newAdmin");
        vm.startPrank(townAdmin);
        registry.grantRole(ADMIN, newAdmin);
        registry.renounceRole(ADMIN, townAdmin);
        vm.stopPrank();
        assertTrue(registry.hasRole(ADMIN, newAdmin));
        assertFalse(registry.hasRole(ADMIN, townAdmin));
    }

    /* ------------------------------------------------------------- module 1 */

    function test_RegisterAndRevoke() public {
        _becomeResident(alice);
        assertTrue(registry.isResident(alice));
        assertEq(registry.residentCount(), 1);

        vm.prank(townAdmin);
        registry.revoke(alice);
        assertFalse(registry.isResident(alice));
    }

    function test_CannotRegisterTwice() public {
        _becomeResident(alice);
        vm.prank(alice);
        vm.expectRevert(ResidentRegistry.AlreadyRegistered.selector);
        registry.register(bytes32("x"));
    }

    function test_StudentCannotRevokeAnother() public {
        _becomeResident(alice);
        vm.prank(bob);
        vm.expectRevert();
        registry.revoke(alice);
    }

    function test_AdminCanCloseRegistration() public {
        vm.prank(townAdmin);
        registry.setOpenRegistration(false);
        vm.prank(alice);
        vm.expectRevert(ResidentRegistry.RegistrationClosed.selector);
        registry.register(bytes32("x"));
    }

    /* ------------------------------------------------------------- module 2 */

    function test_PassportNeedsResidency() public {
        vm.prank(alice);
        vm.expectRevert(TrustvillePassport.NotAResident.selector);
        passport.mint();
    }

    function test_PassportMintsWithTwoStamps() public {
        _becomeResident(alice);
        vm.prank(alice);
        uint256 id = passport.mint();

        assertEq(passport.ownerOf(id), alice);
        assertEq(passport.stampsOf(alice).length, 2);
        assertTrue(passport.hasStamp(alice, 1));
        assertTrue(passport.hasStamp(alice, 2));
        assertTrue(passport.locked(id));
    }

    function test_PassportCannotBeTransferredOrSold() public {
        _becomeResident(alice);
        vm.prank(alice);
        uint256 id = passport.mint();

        vm.prank(alice);
        vm.expectRevert(TrustvillePassport.Soulbound.selector);
        passport.transferFrom(alice, bob, id);
    }

    function test_OnlyStamperRoleCanStamp() public {
        _becomeResident(alice);
        vm.prank(alice);
        passport.mint();

        vm.prank(bob);
        vm.expectRevert();
        passport.stamp(alice, 9);
    }

    function test_TokenUriIsSelfContained() public {
        _becomeResident(alice);
        vm.prank(alice);
        uint256 id = passport.mint();
        string memory uri = passport.tokenURI(id);
        assertEq(_prefix(uri, 29), "data:application/json;base64,");
    }

    /* ------------------------------------------------------------- module 3 */

    function test_ClaimGrantOncePerResident() public {
        _becomeResident(alice);
        vm.prank(alice);
        passport.mint();

        vm.prank(alice);
        bank.claimWelcomeGrant();
        assertEq(token.balanceOf(alice), GRANT);
        assertTrue(passport.hasStamp(alice, bank.MODULE_TOKEN()));

        vm.prank(alice);
        vm.expectRevert(TownBank.AlreadyClaimed.selector);
        bank.claimWelcomeGrant();
    }

    function test_NonResidentCannotClaim() public {
        vm.prank(bob);
        vm.expectRevert(TownBank.NotAResident.selector);
        bank.claimWelcomeGrant();
    }

    function test_ClaimWorksWithoutAPassport() public {
        _becomeResident(alice);
        vm.prank(alice);
        bank.claimWelcomeGrant();
        assertEq(token.balanceOf(alice), GRANT);
    }

    function test_TokensTransferNormally() public {
        _becomeResident(alice);
        vm.prank(alice);
        bank.claimWelcomeGrant();

        vm.prank(alice);
        token.transfer(bob, 25 ether);
        assertEq(token.balanceOf(bob), 25 ether);
        assertEq(token.balanceOf(alice), 75 ether);
    }

    function test_MaxSupplyIsEnforced() public {
        vm.prank(townAdmin);
        bank.setGrantAmount(10_000_001 ether);
        _becomeResident(alice);
        vm.prank(alice);
        vm.expectRevert();
        bank.claimWelcomeGrant();
    }

    function testFuzz_GrantAmountAlwaysArrivesInFull(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 1_000_000 ether);
        vm.prank(townAdmin);
        bank.setGrantAmount(amount);
        _becomeResident(bob);
        vm.prank(bob);
        bank.claimWelcomeGrant();
        assertEq(token.balanceOf(bob), amount);
    }

    function _prefix(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; i++) out[i] = b[i];
        return string(out);
    }
}
