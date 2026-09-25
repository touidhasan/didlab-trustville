// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {CropInsurance} from "../src/CropInsurance.sol";
import {RainOracle} from "../src/RainOracle.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Reading a role off a contract is an external call. Never put one in the argument list
/// of a pranked call — it consumes the prank and the real call comes from the test
/// contract instead. Hoist it to a local first, as every test here does.
contract InsurerTest is Test {
    bytes32 constant ADMIN = 0x00;
    uint32 constant PERIOD = 600; // ten minutes, a lab-sized "day"
    uint32 constant TRIGGER = 5; // under 5mm over the period is a drought
    uint16 constant PREMIUM_BPS = 1000; // 10%

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    RainOracle oracle;
    CropInsurance insurer;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address farmer = makeAddr("farmer");
    address funder = makeAddr("funder");
    address r1 = makeAddr("reporter1");
    address r2 = makeAddr("reporter2");
    address r3 = makeAddr("reporter3");
    address r4 = makeAddr("reporter4");
    address r5 = makeAddr("reporter5");

    function setUp() public {
        vm.warp(PERIOD * 10); // start at period 10, so periods 0..9 are in the past

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

        oracle = new RainOracle(townAdmin, PERIOD, 3);
        insurer = new CropInsurance(
            IERC20(address(token)), oracle, townAdmin, TRIGGER, PREMIUM_BPS, passport
        );
        vm.stopPrank();

        bytes32 stamper = passport.STAMPER_ROLE();
        bytes32 reporter = oracle.REPORTER_ROLE();
        vm.startPrank(townAdmin);
        passport.grantRole(stamper, address(insurer));
        oracle.grantRole(reporter, r1);
        oracle.grantRole(reporter, r2);
        oracle.grantRole(reporter, r3);
        oracle.grantRole(reporter, r4);
        oracle.grantRole(reporter, r5);
        vm.stopPrank();

        for (uint256 i; i < 2; i++) {
            address who = [farmer, funder][i];
            vm.startPrank(who);
            registry.register(keccak256(abi.encodePacked(who)));
            passport.mint();
            bank.claimWelcomeGrant();
            token.approve(address(insurer), type(uint256).max);
            vm.stopPrank();
        }

        vm.prank(funder);
        insurer.fund(800 ether);
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    function _report(uint32 period, address who, uint32 mm) internal {
        vm.prank(who);
        oracle.report(period, mm);
    }

    /* ==================================================================== the oracle */

    function test_MedianOfThreeIsTheMiddleReport() public {
        _report(9, r1, 10);
        _report(9, r2, 2);
        _report(9, r3, 7);
        oracle.finalize(9);

        (bool finalized, uint32 mm, uint32 n) = oracle.reading(9);
        assertTrue(finalized);
        assertEq(mm, 7);
        assertEq(n, 3);
    }

    /// The point of a median: one reporter lying wildly barely moves the answer. With a
    /// mean, 9000 would have dragged the "rainfall" to over 3000mm.
    function test_OneLiarCannotMoveTheAnswer() public {
        _report(9, r1, 10);
        _report(9, r2, 12);
        _report(9, r3, 9000);
        oracle.finalize(9);

        (, uint32 mm,) = oracle.reading(9);
        assertEq(mm, 12, "the liar only shifts the middle by one place");
    }

    /// And the honest limit of the design: control the majority and you control the answer.
    /// No cryptography prevents this — only the cost of running enough reporters.
    function test_AMajorityOfReportersControlsTheAnswer() public {
        _report(9, r1, 40);
        _report(9, r2, 44);
        _report(9, r3, 0);
        _report(9, r4, 0);
        _report(9, r5, 0);
        oracle.finalize(9);

        (, uint32 mm,) = oracle.reading(9);
        assertEq(mm, 0, "three of five decide it");
    }

    function test_EvenCountTakesTheLowerMiddle() public {
        _report(9, r1, 4);
        _report(9, r2, 8);
        _report(9, r3, 6);
        _report(9, r4, 10);
        oracle.finalize(9);

        (, uint32 mm,) = oracle.reading(9);
        assertEq(mm, 6, "never invents a figure nobody reported");
    }

    function test_NobodyReportsTheFuture() public {
        vm.prank(r1);
        vm.expectRevert(RainOracle.PeriodNotOver.selector);
        oracle.report(11, 0);
    }

    function test_NobodyReportsTheCurrentPeriodEither() public {
        uint32 now_ = oracle.currentPeriod();
        vm.prank(r1);
        vm.expectRevert(RainOracle.PeriodNotOver.selector);
        oracle.report(now_, 0);
    }

    function test_AReporterGetsOneVoice() public {
        _report(9, r1, 10);
        vm.prank(r1);
        vm.expectRevert(RainOracle.AlreadyReported.selector);
        oracle.report(9, 3);
    }

    function test_StrangersCannotReport() public {
        address stranger = makeAddr("stranger");
        bytes32 role = oracle.REPORTER_ROLE();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, role
            )
        );
        oracle.report(9, 0);
    }

    function test_FinalizeNeedsTheQuorum() public {
        _report(9, r1, 10);
        _report(9, r2, 12);
        vm.expectRevert(abi.encodeWithSelector(RainOracle.NotEnoughReports.selector, 2, 3));
        oracle.finalize(9);
    }

    function test_FinalizeIsOnceOnlyAndOpenToAnyone() public {
        _report(9, r1, 10);
        _report(9, r2, 12);
        _report(9, r3, 11);

        address passerby = makeAddr("passerby");
        vm.prank(passerby);
        oracle.finalize(9); // no role needed — the caller cannot change the answer

        vm.expectRevert(RainOracle.AlreadyFinalized.selector);
        oracle.finalize(9);
    }

    function test_NoReportsAfterFinalizing() public {
        _report(9, r1, 10);
        _report(9, r2, 12);
        _report(9, r3, 11);
        oracle.finalize(9);

        vm.prank(r4);
        vm.expectRevert(RainOracle.AlreadyFinalized.selector);
        oracle.report(9, 0);
    }

    /// The audit trail stays in submission order, unsorted, so a reporter whose figure sat
    /// far from the median is visible for ever.
    function test_EveryReportStaysReadable() public {
        _report(9, r1, 10);
        _report(9, r2, 9000);
        _report(9, r3, 11);
        oracle.finalize(9);

        (address[] memory who, uint32[] memory mm) = oracle.reportsOf(9);
        assertEq(who.length, 3);
        assertEq(who[1], r2);
        assertEq(mm[1], 9000);
    }

    function test_AnUnreportedPeriodIsNotADrought() public {
        (bool finalized, uint32 mm,) = oracle.reading(8);
        assertFalse(finalized);
        assertEq(mm, 0, "zero, but nobody may act on it");
    }

    /* ================================================================= the insurance */

    function _buy(uint32 period, uint256 coverage) internal returns (uint256 id) {
        vm.prank(farmer);
        id = insurer.buy(period, coverage);
    }

    function test_BuyingReservesTheCoverAndTakesThePremium() public {
        uint256 farmerStart = token.balanceOf(farmer);
        uint256 id = _buy(11, 100 ether);

        assertEq(insurer.reserved(), 100 ether);
        assertEq(insurer.available(), 800 ether + 10 ether - 100 ether, "pool minus the promise");
        assertEq(token.balanceOf(farmer), farmerStart - 10 ether, "10% premium");

        CropInsurance.Policy memory p = insurer.get(id);
        assertEq(p.coverage, 100 ether);
        assertEq(p.triggerMm, TRIGGER);
        assertEq(uint8(p.status), uint8(CropInsurance.Status.Active));
        assertTrue(passport.hasStamp(farmer, 14));
    }

    function test_CannotSellMoreCoverThanThePoolHolds() public {
        vm.prank(farmer);
        vm.expectRevert(
            abi.encodeWithSelector(CropInsurance.NotEnoughInThePool.selector, 800 ether, 900 ether)
        );
        insurer.buy(11, 900 ether);
    }

    function test_CannotInsureAPeriodThatHasBegun() public {
        uint32 now_ = oracle.currentPeriod();
        vm.prank(farmer);
        vm.expectRevert(CropInsurance.PeriodAlreadyStarted.selector);
        insurer.buy(now_, 10 ether);
    }

    function test_DroughtPaysOutWithoutAnyoneDeciding() public {
        uint256 id = _buy(11, 100 ether);
        uint256 farmerAfterPremium = token.balanceOf(farmer);

        vm.warp(PERIOD * 12); // period 11 is over
        _report(11, r1, 1);
        _report(11, r2, 0);
        _report(11, r3, 2);
        oracle.finalize(11);

        bool paid = insurer.settle(id);
        assertTrue(paid);
        assertEq(token.balanceOf(farmer), farmerAfterPremium + 100 ether);
        assertEq(insurer.reserved(), 0, "the promise is discharged");
        assertEq(uint8(insurer.get(id).status), uint8(CropInsurance.Status.PaidOut));
    }

    function test_RainMeansNoPayoutAndTheCoverGoesBackToThePool() public {
        uint256 id = _buy(11, 100 ether);
        uint256 farmerAfterPremium = token.balanceOf(farmer);

        vm.warp(PERIOD * 12);
        _report(11, r1, 12);
        _report(11, r2, 9);
        _report(11, r3, 14);
        oracle.finalize(11);

        bool paid = insurer.settle(id);
        assertFalse(paid);
        assertEq(token.balanceOf(farmer), farmerAfterPremium, "not a penny");
        assertEq(insurer.reserved(), 0);
        assertEq(insurer.available(), 810 ether, "the premium is the insurer's profit");
        assertEq(uint8(insurer.get(id).status), uint8(CropInsurance.Status.Expired));
    }

    function test_AnyoneMaySettleForTheHolder() public {
        uint256 id = _buy(11, 50 ether);
        uint256 farmerAfterPremium = token.balanceOf(farmer);

        vm.warp(PERIOD * 12);
        _report(11, r1, 0);
        _report(11, r2, 1);
        _report(11, r3, 0);
        oracle.finalize(11);

        address passerby = makeAddr("passerby");
        vm.prank(passerby);
        insurer.settle(id);

        assertEq(token.balanceOf(farmer), farmerAfterPremium + 50 ether, "paid to the holder");
        assertEq(token.balanceOf(passerby), 0, "not to the sender");
    }

    function test_CannotSettleBeforeTheOracleHasSpoken() public {
        uint256 id = _buy(11, 50 ether);
        vm.warp(PERIOD * 12);
        _report(11, r1, 0);
        _report(11, r2, 0); // one short of quorum

        vm.expectRevert(CropInsurance.NoReadingYet.selector);
        insurer.settle(id);
    }

    function test_CannotSettleTwice() public {
        uint256 id = _buy(11, 50 ether);
        vm.warp(PERIOD * 12);
        _report(11, r1, 0);
        _report(11, r2, 0);
        _report(11, r3, 0);
        oracle.finalize(11);

        insurer.settle(id);
        vm.expectRevert(CropInsurance.AlreadySettled.selector);
        insurer.settle(id);
    }

    /// The trigger is frozen when the policy is sold. An insurer that could move it after
    /// taking the premium is not selling insurance.
    function test_ChangingTheTermsDoesNotTouchLivePolicies() public {
        uint256 id = _buy(11, 100 ether);

        vm.prank(townAdmin);
        insurer.setTerms(0, PREMIUM_BPS); // nothing would ever pay out under the new terms

        vm.warp(PERIOD * 12);
        _report(11, r1, 1);
        _report(11, r2, 1);
        _report(11, r3, 1);
        oracle.finalize(11);

        assertTrue(insurer.settle(id), "sold at 5mm, settled at 5mm");
    }

    function test_SurplusCanBeWithdrawnButReservedCoverCannot() public {
        _buy(11, 700 ether); // 70 premium in, 700 reserved
        uint256 free = insurer.available(); // 800 + 70 - 700 = 170

        vm.prank(townAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(CropInsurance.NotEnoughInThePool.selector, free, free + 1)
        );
        insurer.withdrawSurplus(townAdmin, free + 1);

        vm.prank(townAdmin);
        insurer.withdrawSurplus(townAdmin, free);
        assertEq(token.balanceOf(address(insurer)), 700 ether, "exactly the promise remains");
    }

    /// However the policies are sized, the pool always holds at least what it has promised.
    function testFuzz_ThePoolNeverPromisesWhatItDoesNotHold(uint96 a, uint96 b) public {
        uint256 first = bound(uint256(a), 1 ether, 400 ether);
        uint256 second = bound(uint256(b), 1 ether, 400 ether);

        vm.prank(farmer);
        insurer.buy(11, first);
        vm.prank(farmer);
        insurer.buy(12, second);

        assertGe(token.balanceOf(address(insurer)), insurer.reserved());
    }
}
