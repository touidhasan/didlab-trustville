// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {PropertyDeeds} from "../src/PropertyDeeds.sol";
import {RentEscrow} from "../src/RentEscrow.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";
import {VoteToken} from "../src/VoteToken.sol";

contract HousingTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    PropertyDeeds deeds;
    RentEscrow leases;
    VoteToken votes;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address owner = makeAddr("owner"); // landlord
    address tenant = makeAddr("tenant");
    address buyer = makeAddr("buyer");

    function setUp() public {
        vm.startPrank(deployer);
        registry = new ResidentRegistry(deployer);
        passport = new TrustvillePassport(deployer, registry);
        token = new TownToken(deployer, 10_000_000 ether);
        bank = new TownBank(deployer, registry, token, passport, 1000 ether);
        token.grantRole(token.MINTER_ROLE(), address(bank));
        passport.grantRole(passport.STAMPER_ROLE(), address(bank));
        registry.grantRole(registry.REGISTRAR_ROLE(), townAdmin);
        _handOver(address(registry));
        _handOver(address(passport));
        _handOver(address(token));
        _handOver(address(bank));
        registry.renounceRole(registry.REGISTRAR_ROLE(), deployer);

        deeds = new PropertyDeeds(townAdmin, registry, passport);
        leases = new RentEscrow(townAdmin, IERC20(address(token)), IERC721(address(deeds)), passport);
        votes = new VoteToken(IERC20(address(token)));
        vm.stopPrank();

        bytes32 stamper = passport.STAMPER_ROLE();
        vm.startPrank(townAdmin);
        passport.grantRole(stamper, address(deeds));
        passport.grantRole(stamper, address(leases));
        vm.stopPrank();

        for (uint256 i; i < 3; i++) {
            address who = [owner, tenant, buyer][i];
            vm.startPrank(who);
            registry.register(keccak256(abi.encodePacked(who)));
            passport.mint();
            bank.claimWelcomeGrant();
            vm.stopPrank();
        }
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    function _deed() internal returns (uint256 id) {
        vm.prank(owner);
        id = deeds.register("12 Mill Lane", keccak256("title.pdf"));
    }

    /* ------------------------------------------------------------- module 9 */

    function test_RegisterMintsADeedAndStamps() public {
        uint256 id = _deed();
        assertEq(deeds.ownerOf(id), owner);
        assertEq(deeds.get(id).addressLine, "12 Mill Lane");
        assertFalse(deeds.get(id).certified); // a claim until the town says otherwise
        assertTrue(passport.hasStamp(owner, 9));
    }

    function test_DeedsAreTransferable_UnlikeThePassport() public {
        uint256 id = _deed();
        vm.prank(owner);
        deeds.transferFrom(owner, buyer, id);
        assertEq(deeds.ownerOf(id), buyer);

        // the Passport, same standard, refuses the same call
        uint256 passportId = passport.passportOf(owner);
        vm.prank(owner);
        vm.expectRevert(TrustvillePassport.Soulbound.selector);
        passport.transferFrom(owner, buyer, passportId);
    }

    function test_CertificationIsClearedOnTransfer() public {
        uint256 id = _deed();
        vm.prank(townAdmin);
        deeds.certify(id);
        assertTrue(deeds.get(id).certified);

        vm.prank(owner);
        deeds.transferFrom(owner, buyer, id);
        assertFalse(deeds.get(id).certified); // the town vouched for the old owner only
    }

    function test_OnlyCertifierCertifies() public {
        uint256 id = _deed();
        vm.prank(owner);
        vm.expectRevert();
        deeds.certify(id);
    }

    function test_NonResidentCannotRegister() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(PropertyDeeds.NotAResident.selector);
        deeds.register("Nowhere", bytes32(0));
    }

    /* ------------------------------------------------------------ module 10 */

    function _lease(uint256 rent, uint256 deposit) internal returns (uint256 id, uint256 deedId) {
        deedId = _deed();
        vm.prank(owner);
        id = leases.offerLease(deedId, tenant, rent, deposit, 2 hours, 1 hours);
    }

    function _accept(uint256 id, uint256 deposit) internal {
        vm.startPrank(tenant);
        token.approve(address(leases), deposit);
        leases.acceptLease(id);
        vm.stopPrank();
    }

    function test_OnlyDeedOwnerCanLet() public {
        uint256 deedId = _deed();
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(RentEscrow.NotTheDeedOwner.selector, owner));
        leases.offerLease(deedId, tenant, 1 ether, 1 ether, 2 hours, 1 hours);
    }

    function test_DepositSitsInTheContractNotWithTheLandlord() public {
        (uint256 id,) = _lease(10 ether, 100 ether);
        uint256 landlordBefore = token.balanceOf(owner);
        _accept(id, 100 ether);

        assertEq(token.balanceOf(address(leases)), 100 ether);
        assertEq(token.balanceOf(owner), landlordBefore);
        assertTrue(passport.hasStamp(tenant, 10));
    }

    function test_RentGoesStraightToTheLandlord() public {
        (uint256 id,) = _lease(10 ether, 50 ether);
        _accept(id, 50 ether);
        uint256 before = token.balanceOf(owner);

        vm.startPrank(tenant);
        token.approve(address(leases), 20 ether);
        leases.payRent(id);
        leases.payRent(id);
        vm.stopPrank();

        assertEq(token.balanceOf(owner), before + 20 ether);
        assertEq(leases.get(id).rentPaid, 2);
    }

    function test_TenantTakesDepositBackWhenNoClaim() public {
        (uint256 id,) = _lease(0, 100 ether);
        uint256 before = token.balanceOf(tenant);
        _accept(id, 100 ether);

        vm.warp(block.timestamp + 2 hours + 1 hours + 1); // lease over, window closed
        vm.prank(tenant);
        leases.returnDeposit(id);
        assertEq(token.balanceOf(tenant), before); // whole again, nobody had to agree
    }

    function test_TenantCannotTakeItBackDuringTheClaimWindow() public {
        (uint256 id,) = _lease(0, 100 ether);
        _accept(id, 100 ether);
        uint64 until = leases.get(id).endsAt + leases.get(id).claimWindow;

        vm.warp(leases.get(id).endsAt + 1);
        vm.prank(tenant);
        vm.expectRevert(abi.encodeWithSelector(RentEscrow.ClaimWindowOpen.selector, until));
        leases.returnDeposit(id);
    }

    function test_LandlordCannotClaimBeforeTheLeaseEnds() public {
        (uint256 id,) = _lease(0, 100 ether);
        _accept(id, 100 ether);
        uint64 endsAt = leases.get(id).endsAt;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RentEscrow.LeaseNotEnded.selector, endsAt));
        leases.claimDeposit(id, 50 ether, "damage");
    }

    function test_LandlordCannotClaimAfterTheWindow() public {
        (uint256 id,) = _lease(0, 100 ether);
        _accept(id, 100 ether);
        uint64 until = leases.get(id).endsAt + leases.get(id).claimWindow;

        vm.warp(until + 1);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RentEscrow.ClaimWindowClosed.selector, until));
        leases.claimDeposit(id, 50 ether, "too late");
    }

    function test_ClaimIsSplitByTheArbiter() public {
        (uint256 id,) = _lease(0, 100 ether);
        _accept(id, 100 ether);
        uint256 landlordBefore = token.balanceOf(owner);
        uint256 tenantBefore = token.balanceOf(tenant);

        vm.warp(leases.get(id).endsAt + 1);
        vm.prank(owner);
        leases.claimDeposit(id, 80 ether, "broken window");

        vm.prank(townAdmin);
        leases.resolveClaim(id, 30 ether); // arbiter awards less than claimed

        assertEq(token.balanceOf(owner), landlordBefore + 30 ether);
        assertEq(token.balanceOf(tenant), tenantBefore + 70 ether);
        assertEq(token.balanceOf(address(leases)), 0);
    }

    function test_ClaimCannotExceedTheDeposit() public {
        (uint256 id,) = _lease(0, 100 ether);
        _accept(id, 100 ether);
        vm.warp(leases.get(id).endsAt + 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RentEscrow.ClaimTooLarge.selector, 100 ether));
        leases.claimDeposit(id, 150 ether, "greedy");
    }

    function test_OnlyArbiterResolves() public {
        (uint256 id,) = _lease(0, 50 ether);
        _accept(id, 50 ether);
        vm.warp(leases.get(id).endsAt + 1);
        vm.prank(owner);
        leases.claimDeposit(id, 10 ether, "cleaning");

        vm.prank(owner);
        vm.expectRevert();
        leases.resolveClaim(id, 10 ether);
    }

    function test_CannotPayRentAfterTheLeaseEnds() public {
        (uint256 id,) = _lease(5 ether, 10 ether);
        _accept(id, 10 ether);
        vm.warp(leases.get(id).endsAt + 1);

        vm.startPrank(tenant);
        token.approve(address(leases), 5 ether);
        vm.expectRevert(RentEscrow.LeaseEnded.selector);
        leases.payRent(id);
        vm.stopPrank();
    }

    /* ------------------------------------------------------- voting wrapper */

    function test_WrapGivesVotingPowerOnlyAfterDelegating() public {
        vm.startPrank(owner);
        token.approve(address(votes), 500 ether);
        votes.depositFor(owner, 500 ether);
        vm.stopPrank();

        assertEq(votes.balanceOf(owner), 500 ether);
        assertEq(votes.getVotes(owner), 0); // held, but voting for nobody

        vm.prank(owner);
        votes.delegate(owner);
        assertEq(votes.getVotes(owner), 500 ether);
    }

    function test_DepositAndSelfDelegateDoesBothAtOnce() public {
        vm.startPrank(tenant);
        token.approve(address(votes), 200 ether);
        votes.depositAndSelfDelegate(200 ether);
        vm.stopPrank();
        assertEq(votes.getVotes(tenant), 200 ether);
    }

    function test_UnwrapReturnsTheTownToken() public {
        uint256 before = token.balanceOf(owner);
        vm.startPrank(owner);
        token.approve(address(votes), 300 ether);
        votes.depositAndSelfDelegate(300 ether);
        assertEq(token.balanceOf(owner), before - 300 ether);
        votes.withdrawTo(owner, 300 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(owner), before);
        assertEq(votes.getVotes(owner), 0);
    }

    function test_PastVotesAreCheckpointed() public {
        vm.startPrank(owner);
        token.approve(address(votes), 400 ether);
        votes.depositAndSelfDelegate(400 ether);
        vm.stopPrank();

        // The token counts by TIMESTAMP (ERC-6372), so snapshots are moments, not blocks.
        assertEq(votes.CLOCK_MODE(), "mode=timestamp");
        uint256 snapshot = block.timestamp;
        vm.warp(block.timestamp + 10);

        vm.prank(owner);
        votes.withdrawTo(owner, 400 ether); // sell up after the snapshot

        vm.warp(block.timestamp + 10);
        assertEq(votes.getPastVotes(owner, snapshot), 400 ether); // history is what counts
        assertEq(votes.getVotes(owner), 0);
    }
}
