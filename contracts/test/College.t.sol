// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";
import {EventTickets} from "../src/EventTickets.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

contract CollegeTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    CertificateRegistry certs;
    EventTickets tickets;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address college = makeAddr("college"); // issuer / organiser
    address ana = makeAddr("ana");
    address ben = makeAddr("ben");

    uint64 startsAt;

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

        certs = new CertificateRegistry(registry, passport);
        tickets = new EventTickets(IERC20(address(token)), registry, passport);
        vm.stopPrank();

        bytes32 stamper = passport.STAMPER_ROLE();
        vm.startPrank(townAdmin);
        passport.grantRole(stamper, address(certs));
        passport.grantRole(stamper, address(tickets));
        vm.stopPrank();

        for (uint256 i; i < 3; i++) {
            address who = [college, ana, ben][i];
            vm.startPrank(who);
            registry.register(keccak256(abi.encodePacked(who)));
            passport.mint();
            bank.claimWelcomeGrant();
            vm.stopPrank();
        }
        startsAt = uint64(block.timestamp + 7 days);
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    /* ------------------------------------------------------------- module 7 */

    function _issue(address to, bytes32 h) internal returns (uint256 id) {
        vm.prank(college);
        id = certs.issue(to, "Blockchain Security", h);
    }

    function test_IssueAndVerify() public {
        uint256 id = _issue(ana, keccak256("ana.pdf"));

        (bool known, bool valid, address issuer, address holder, string memory course) =
            certs.verifyDocument(keccak256("ana.pdf"));
        assertTrue(known);
        assertTrue(valid);
        assertEq(issuer, college);
        assertEq(holder, ana);
        assertEq(course, "Blockchain Security");
        assertEq(certs.certificatesOf(ana)[0], id);
        assertTrue(passport.hasStamp(college, 7));
    }

    function test_UnknownDocumentVerifiesAsUnknown() public view {
        (bool known, bool valid,,,) = certs.verifyDocument(keccak256("never-issued.pdf"));
        assertFalse(known);
        assertFalse(valid);
    }

    function test_AlteredDocumentDoesNotMatch() public {
        _issue(ana, keccak256("ana.pdf"));
        (bool known,,,,) = certs.verifyDocument(keccak256("ana.pdf (edited)"));
        assertFalse(known); // one changed byte, and the hash no longer matches
    }

    function test_OnlyIssuerRevokes() public {
        uint256 id = _issue(ana, keccak256("ana.pdf"));

        vm.prank(ana); // the holder cannot un-revoke or revoke their own
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.NotTheIssuer.selector, college));
        certs.revoke(id, "nope");

        vm.prank(college);
        certs.revoke(id, "issued in error");
        assertFalse(certs.isValid(id));

        // the record survives revocation — history is not erased
        CertificateRegistry.Certificate memory c = certs.get(id);
        assertEq(c.holder, ana);
        assertTrue(c.revokedAt > 0);
    }

    function test_CannotRegisterSameDocumentTwice() public {
        uint256 id = _issue(ana, keccak256("ana.pdf"));
        vm.prank(college);
        vm.expectRevert(abi.encodeWithSelector(CertificateRegistry.DocumentAlreadyRegistered.selector, id));
        certs.issue(ben, "Blockchain Security", keccak256("ana.pdf"));
    }

    function test_CannotIssueToYourself() public {
        vm.prank(college);
        vm.expectRevert(CertificateRegistry.SelfIssue.selector);
        certs.issue(college, "Self Study", keccak256("self.pdf"));
    }

    function test_NonResidentCannotIssue() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(CertificateRegistry.NotAResident.selector);
        certs.issue(ana, "Fake", keccak256("fake.pdf"));
    }

    /* ------------------------------------------------------------- module 8 */

    function _event(uint256 price, uint32 capacity) internal returns (uint256 id) {
        vm.prank(college);
        id = tickets.createEvent("Graduation night", price, capacity, startsAt);
    }

    function _buy(address who, uint256 id, uint32 qty, uint256 price) internal {
        vm.startPrank(who);
        token.approve(address(tickets), price * qty);
        tickets.buy(id, qty);
        vm.stopPrank();
    }

    function test_BuyMintsTicketsAndHoldsTheMoney() public {
        uint256 id = _event(10 ether, 100);
        uint256 organiserBefore = token.balanceOf(college);

        _buy(ana, id, 3, 10 ether);

        assertEq(tickets.balanceOf(ana, id), 3);
        assertEq(token.balanceOf(address(tickets)), 30 ether); // held, not paid out
        assertEq(token.balanceOf(college), organiserBefore); // organiser not paid yet
        assertTrue(passport.hasStamp(ana, 8));
    }

    function test_CapacityIsEnforced() public {
        uint256 id = _event(1 ether, 2);
        _buy(ana, id, 2, 1 ether);

        vm.startPrank(ben);
        token.approve(address(tickets), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(EventTickets.SoldOut.selector, uint32(0)));
        tickets.buy(id, 1);
        vm.stopPrank();
    }

    function test_RedeemBurnsSoATicketCannotBeReused() public {
        uint256 id = _event(1 ether, 10);
        _buy(ana, id, 2, 1 ether);

        vm.prank(ana);
        tickets.redeem(id, 2);
        assertEq(tickets.balanceOf(ana, id), 0);
        assertEq(tickets.get(id).redeemed, 2);

        vm.prank(ana);
        vm.expectRevert(EventTickets.NotEnoughTickets.selector);
        tickets.redeem(id, 1);
    }

    function test_TicketsAreTransferable() public {
        uint256 id = _event(1 ether, 10);
        _buy(ana, id, 2, 1 ether);

        vm.prank(ana);
        tickets.safeTransferFrom(ana, ben, id, 1, "");
        assertEq(tickets.balanceOf(ben, id), 1);
        assertEq(tickets.balanceOf(ana, id), 1);
    }

    function test_CancelRefundsBuyers() public {
        uint256 id = _event(10 ether, 10);
        uint256 anaBefore = token.balanceOf(ana);
        _buy(ana, id, 2, 10 ether);

        vm.prank(college);
        tickets.cancel(id);

        vm.prank(ana);
        tickets.refund(id);
        assertEq(token.balanceOf(ana), anaBefore); // whole again
        assertEq(tickets.balanceOf(ana, id), 0); // tickets burned

        vm.prank(ana);
        vm.expectRevert(EventTickets.NothingToRefund.selector);
        tickets.refund(id);
    }

    function test_OrganiserCannotTakeMoneyBeforeTheEvent() public {
        uint256 id = _event(10 ether, 10);
        _buy(ana, id, 1, 10 ether);

        vm.prank(college);
        vm.expectRevert(EventTickets.EventNotStarted.selector);
        tickets.withdrawProceeds(id);
    }

    function test_OrganiserWithdrawsAfterStart() public {
        uint256 id = _event(10 ether, 10);
        _buy(ana, id, 2, 10 ether);
        uint256 before = token.balanceOf(college);

        vm.warp(startsAt + 1);
        vm.prank(college);
        tickets.withdrawProceeds(id);
        assertEq(token.balanceOf(college), before + 20 ether);

        vm.prank(college);
        vm.expectRevert(EventTickets.AlreadyWithdrawn.selector);
        tickets.withdrawProceeds(id);
    }

    function test_CancelledEventPaysNobodyButBuyers() public {
        uint256 id = _event(10 ether, 10);
        _buy(ana, id, 1, 10 ether);
        vm.prank(college);
        tickets.cancel(id);

        vm.warp(startsAt + 1);
        vm.prank(college);
        vm.expectRevert(EventTickets.EventCancelledError.selector);
        tickets.withdrawProceeds(id);
    }

    function test_OnlyOrganiserCancels() public {
        uint256 id = _event(1 ether, 10);
        vm.prank(ben);
        vm.expectRevert(abi.encodeWithSelector(EventTickets.NotTheOrganiser.selector, college));
        tickets.cancel(id);
    }

    function test_CannotBuyAfterStart() public {
        uint256 id = _event(1 ether, 10);
        vm.warp(startsAt + 1);
        vm.startPrank(ana);
        token.approve(address(tickets), 1 ether);
        vm.expectRevert(EventTickets.EventStarted.selector);
        tickets.buy(id, 1);
        vm.stopPrank();
    }

    function test_UriIsSelfContained() public {
        uint256 id = _event(1 ether, 10);
        string memory u = tickets.uri(id);
        bytes memory b = bytes(u);
        bytes memory prefix = new bytes(29);
        for (uint256 i; i < 29; i++) prefix[i] = b[i];
        assertEq(string(prefix), "data:application/json;base64,");
    }

    function testFuzz_MoneyHeldAlwaysMatchesTicketsSold(uint8 qty) public {
        vm.assume(qty > 0 && qty <= 50);
        uint256 id = _event(2 ether, 50);
        _buy(ana, id, qty, 2 ether);
        assertEq(token.balanceOf(address(tickets)), uint256(qty) * 2 ether);
        assertEq(tickets.get(id).sold, qty);
    }
}
