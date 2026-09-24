// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ProductRegistry} from "../src/ProductRegistry.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {SealedAuction} from "../src/SealedAuction.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownEscrow} from "../src/TownEscrow.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

contract MarketTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    ProductRegistry products;
    TownEscrow escrow;
    SealedAuction auction;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address alice = makeAddr("alice"); // seller
    address bob = makeAddr("bob"); // buyer
    address carol = makeAddr("carol"); // rival bidder

    function setUp() public {
        // D1, exactly as DeployTown does it
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

        // D2a, as DeployMarket does it
        products = new ProductRegistry(registry, passport);
        escrow = new TownEscrow(townAdmin, IERC20(address(token)), passport);
        auction = new SealedAuction(IERC20(address(token)), passport);
        vm.stopPrank();

        // the admin-only step (GrantMarketRoles)
        vm.startPrank(townAdmin);
        passport.grantRole(passport.STAMPER_ROLE(), address(products));
        passport.grantRole(passport.STAMPER_ROLE(), address(escrow));
        passport.grantRole(passport.STAMPER_ROLE(), address(auction));
        vm.stopPrank();

        for (uint256 i; i < 3; i++) {
            address who = [alice, bob, carol][i];
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

    function _product() internal returns (uint256 id) {
        vm.prank(alice);
        id = products.register("Jar of honey", "Miller farm", keccak256("cert"));
    }

    /* ------------------------------------------------------------- module 4 */

    function test_RegisterProductAndStamp() public {
        uint256 id = _product();
        ProductRegistry.Product memory p = products.get(id);
        assertEq(p.creator, alice);
        assertEq(p.holder, alice);
        assertEq(p.name, "Jar of honey");
        assertTrue(passport.hasStamp(alice, 4));
    }

    function test_NonResidentCannotRegister() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(ProductRegistry.NotAResident.selector);
        products.register("Fake", "Nowhere", bytes32(0));
    }

    function test_CustodyMovesOnlyByHolder() public {
        uint256 id = _product();

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ProductRegistry.NotTheHolder.selector, alice));
        products.transferCustody(id, carol, "steal");

        vm.prank(alice);
        products.transferCustody(id, bob, "sold at market");
        assertEq(products.get(id).holder, bob);
        assertEq(products.get(id).transfers, 1);

        // now bob can move it on, alice cannot
        vm.prank(bob);
        products.transferCustody(id, carol, "resold");
        assertEq(products.get(id).holder, carol);
    }

    function test_RegisteringStillWorksWithoutStamperRole() public {
        // Read the role FIRST: a call between vm.prank and the real call consumes the prank.
        bytes32 stamper = passport.STAMPER_ROLE();
        vm.prank(townAdmin);
        passport.revokeRole(stamper, address(products));

        vm.prank(bob);
        uint256 id = products.register("Bread", "Bakery", bytes32(0));
        assertEq(products.get(id).creator, bob);
        assertFalse(passport.hasStamp(bob, 4)); // no stamp, but no failure either
    }

    /* ------------------------------------------------------------- module 5 */

    function _order(uint256 amount) internal returns (uint256 id) {
        vm.startPrank(bob);
        token.approve(address(escrow), amount);
        id = escrow.createOrder(alice, amount, 0, 1 hours);
        vm.stopPrank();
    }

    function test_EscrowHoldsFundsUntilConfirmed() public {
        uint256 before = token.balanceOf(alice);
        uint256 id = _order(50 ether);

        assertEq(token.balanceOf(address(escrow)), 50 ether);
        assertEq(token.balanceOf(alice), before); // seller not paid yet

        vm.prank(bob);
        escrow.confirmReceipt(id);

        assertEq(token.balanceOf(alice), before + 50 ether);
        assertEq(token.balanceOf(address(escrow)), 0);
        assertTrue(passport.hasStamp(bob, 5));
    }

    function test_SellerCannotTakeFundsEarly() public {
        uint256 id = _order(10 ether);
        uint64 deadline = escrow.get(id).deadline; // read before pranking
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TownEscrow.TooEarly.selector, deadline));
        escrow.claimAfterWindow(id);
    }

    function test_SellerClaimsAfterWindow() public {
        uint256 id = _order(10 ether);
        uint256 before = token.balanceOf(alice);
        vm.warp(block.timestamp + 1 hours + 1);
        vm.prank(alice);
        escrow.claimAfterWindow(id);
        assertEq(token.balanceOf(alice), before + 10 ether);
    }

    function test_DisputeFreezesAndArbiterRefunds() public {
        uint256 id = _order(30 ether);
        uint256 buyerBefore = token.balanceOf(bob);

        vm.prank(bob);
        escrow.dispute(id);

        // frozen: the seller cannot claim even once the window passes
        vm.warp(block.timestamp + 2 hours);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(TownEscrow.WrongState.selector, TownEscrow.State.Disputed));
        escrow.claimAfterWindow(id);

        vm.prank(townAdmin);
        escrow.resolve(id, false); // refund the buyer
        assertEq(token.balanceOf(bob), buyerBefore + 30 ether);
    }

    function test_OnlyArbiterResolves() public {
        uint256 id = _order(5 ether);
        vm.prank(bob);
        escrow.dispute(id);
        vm.prank(carol);
        vm.expectRevert();
        escrow.resolve(id, true);
    }

    function test_CannotConfirmTwice() public {
        uint256 id = _order(5 ether);
        vm.startPrank(bob);
        escrow.confirmReceipt(id);
        vm.expectRevert(abi.encodeWithSelector(TownEscrow.WrongState.selector, TownEscrow.State.Released));
        escrow.confirmReceipt(id);
        vm.stopPrank();
    }

    function test_OrdersAreListedForBothParties() public {
        uint256 id = _order(5 ether);
        assertEq(escrow.ordersOf(bob)[0], id);
        assertEq(escrow.ordersOf(alice)[0], id);
    }

    /* ------------------------------------------------------------- module 6 */

    function _auction() internal returns (uint256 id) {
        vm.prank(alice);
        id = auction.createAuction("Antique clock", 0, 10 minutes, 10 minutes);
    }

    function _commit(address who, uint256 id, uint256 amount, bytes32 salt) internal {
        vm.prank(who);
        auction.commitBid(id, keccak256(abi.encodePacked(who, amount, salt)));
    }

    function test_CommitHidesTheBidThenRevealDecides() public {
        uint256 id = _auction();
        _commit(bob, id, 40 ether, "s1");
        _commit(carol, id, 60 ether, "s2");

        // nothing readable but a hash during the commit phase
        assertTrue(auction.commitmentOf(id, bob) != bytes32(0));
        assertEq(auction.get(id).highBid, 0);

        vm.warp(block.timestamp + 11 minutes);

        vm.startPrank(bob);
        token.approve(address(auction), 40 ether);
        auction.revealBid(id, 40 ether, "s1");
        vm.stopPrank();

        vm.startPrank(carol);
        token.approve(address(auction), 60 ether);
        auction.revealBid(id, 60 ether, "s2");
        vm.stopPrank();

        assertEq(auction.get(id).highBidder, carol);
        assertEq(auction.get(id).highBid, 60 ether);
        assertEq(auction.refunds(bob), 40 ether); // outbid, waiting to be withdrawn
        assertTrue(passport.hasStamp(carol, 6));
    }

    function test_WrongSaltCannotReveal() public {
        uint256 id = _auction();
        _commit(bob, id, 40 ether, "s1");
        vm.warp(block.timestamp + 11 minutes);

        vm.startPrank(bob);
        token.approve(address(auction), 40 ether);
        vm.expectRevert(SealedAuction.BadReveal.selector);
        auction.revealBid(id, 40 ether, "wrong-salt");
        vm.expectRevert(SealedAuction.BadReveal.selector);
        auction.revealBid(id, 99 ether, "s1"); // different amount, same salt
        vm.stopPrank();
    }

    function test_CannotCommitAfterPhaseOrRevealEarly() public {
        uint256 id = _auction();

        vm.prank(bob);
        vm.expectRevert(SealedAuction.NotInRevealPhase.selector);
        auction.revealBid(id, 1 ether, "s");

        vm.warp(block.timestamp + 11 minutes);
        vm.prank(carol);
        vm.expectRevert(SealedAuction.NotInCommitPhase.selector);
        auction.commitBid(id, keccak256("late"));
    }

    function test_SettlePaysSellerAndLoserWithdraws() public {
        uint256 id = _auction();
        _commit(bob, id, 40 ether, "s1");
        _commit(carol, id, 60 ether, "s2");
        vm.warp(block.timestamp + 11 minutes);

        vm.startPrank(bob);
        token.approve(address(auction), 40 ether);
        auction.revealBid(id, 40 ether, "s1");
        vm.stopPrank();
        vm.startPrank(carol);
        token.approve(address(auction), 60 ether);
        auction.revealBid(id, 60 ether, "s2");
        vm.stopPrank();

        vm.warp(block.timestamp + 11 minutes);
        uint256 sellerBefore = token.balanceOf(alice);
        auction.settle(id); // anyone may settle
        assertEq(token.balanceOf(alice), sellerBefore + 60 ether);

        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        auction.withdrawRefund();
        assertEq(token.balanceOf(bob), bobBefore + 40 ether);

        vm.prank(bob);
        vm.expectRevert(SealedAuction.NothingToWithdraw.selector);
        auction.withdrawRefund();
    }

    function test_SellerCannotBidOnOwnAuction() public {
        uint256 id = _auction();
        vm.prank(alice);
        vm.expectRevert(SealedAuction.SellerCannotBid.selector);
        auction.commitBid(id, keccak256("x"));
    }

    function test_UnrevealedBidJustLoses() public {
        uint256 id = _auction();
        _commit(bob, id, 500 ether, "s1"); // biggest bid, never revealed
        _commit(carol, id, 5 ether, "s2");
        vm.warp(block.timestamp + 11 minutes);

        vm.startPrank(carol);
        token.approve(address(auction), 5 ether);
        auction.revealBid(id, 5 ether, "s2");
        vm.stopPrank();

        vm.warp(block.timestamp + 11 minutes);
        auction.settle(id);
        assertEq(auction.get(id).highBidder, carol);
        assertEq(token.balanceOf(address(auction)), 0); // nothing stuck
    }

    function test_HashBidHelperMatchesTheContract() public view {
        assertEq(
            auction.hashBid(bob, 7 ether, "salt"), keccak256(abi.encodePacked(bob, uint256(7 ether), bytes32("salt")))
        );
    }
}
