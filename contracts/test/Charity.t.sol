// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownCharity} from "../src/TownCharity.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

contract CharityTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    TownCharity charity;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address alice = makeAddr("alice"); // beneficiary — runs the campaign
    address bob = makeAddr("bob"); // donor
    address carol = makeAddr("carol"); // donor

    uint256 constant GOAL = 300 ether;
    uint64 constant WINDOW = 1 hours;

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

        charity = new TownCharity(IERC20(address(token)), townAdmin, passport);
        vm.stopPrank();

        // Read the role BEFORE pranking. A view call in the argument list is still an
        // external call, and it consumes the prank — the grant would then come from the
        // test contract and revert. This has bitten this repository four times.
        bytes32 stamper = passport.STAMPER_ROLE();
        vm.prank(townAdmin);
        passport.grantRole(stamper, address(charity));

        for (uint256 i; i < 3; i++) {
            address who = [alice, bob, carol][i];
            vm.startPrank(who);
            registry.register(keccak256(abi.encodePacked(who)));
            passport.mint();
            bank.claimWelcomeGrant();
            token.approve(address(charity), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    /// A well pump in two stages: dig it, then connect it.
    function _campaign() internal returns (uint256 id) {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;
        string[] memory what = new string[](2);
        what[0] = "Dig the well";
        what[1] = "Install the pump";
        vm.prank(alice);
        id = charity.create("A well for Mill Lane", GOAL, WINDOW, amounts, what);
    }

    function _fund(uint256 id) internal {
        vm.prank(bob);
        charity.pledge(id, 200 ether);
        vm.prank(carol);
        charity.pledge(id, 100 ether);
    }

    /* ------------------------------------------------------------- the happy path */

    function test_FundThenReleaseOneTrancheAtATime() public {
        uint256 id = _campaign();
        _fund(id);

        assertEq(uint8(charity.get(id).state), uint8(TownCharity.State.Funded));
        assertEq(token.balanceOf(address(charity)), GOAL);
        uint256 aliceStart = token.balanceOf(alice);

        // Milestone 0: evidence, then approval, then exactly one tranche.
        vm.prank(alice);
        charity.submitEvidence(id, 0, keccak256("photos of the hole"));
        vm.prank(townAdmin);
        charity.approveMilestone(id, 0);

        assertEq(token.balanceOf(alice), aliceStart + 100 ether, "first tranche only");
        assertEq(token.balanceOf(address(charity)), 200 ether, "the rest stays locked");
        assertEq(uint8(charity.get(id).state), uint8(TownCharity.State.Funded));

        // Milestone 1 completes the campaign.
        vm.prank(alice);
        charity.submitEvidence(id, 1, keccak256("photos of the pump"));
        vm.prank(townAdmin);
        charity.approveMilestone(id, 1);

        assertEq(token.balanceOf(alice), aliceStart + GOAL);
        assertEq(token.balanceOf(address(charity)), 0, "nothing left behind");
        assertEq(uint8(charity.get(id).state), uint8(TownCharity.State.Completed));
    }

    function test_PledgingStampsThePassport() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 10 ether);
        assertTrue(passport.hasStamp(bob, 13));
    }

    /* ------------------------------------------------ what the money cannot be made to do */

    function test_MeetingTheGoalDoesNotReleaseAnything() public {
        uint256 id = _campaign();
        uint256 aliceStart = token.balanceOf(alice);
        _fund(id);
        assertEq(token.balanceOf(alice), aliceStart, "goal met is not money paid");
        assertEq(token.balanceOf(address(charity)), GOAL);
    }

    function test_BeneficiaryCannotApproveTheirOwnMilestone() public {
        uint256 id = _campaign();
        _fund(id);
        vm.prank(alice);
        charity.submitEvidence(id, 0, keccak256("photos"));

        bytes32 arbiter = charity.ARBITER_ROLE(); // read before pranking — see setUp
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, arbiter
            )
        );
        charity.approveMilestone(id, 0);
    }

    function test_ArbiterCannotPayBeforeEvidence() public {
        uint256 id = _campaign();
        _fund(id);
        vm.prank(townAdmin);
        vm.expectRevert(TownCharity.WrongStep.selector);
        charity.approveMilestone(id, 0);
    }

    function test_AMilestoneCannotBePaidTwice() public {
        uint256 id = _campaign();
        _fund(id);
        vm.prank(alice);
        charity.submitEvidence(id, 0, keccak256("photos"));
        vm.prank(townAdmin);
        charity.approveMilestone(id, 0);

        vm.prank(townAdmin);
        vm.expectRevert(TownCharity.WrongStep.selector);
        charity.approveMilestone(id, 0);
    }

    function test_NothingIsReleasedBeforeTheGoalIsMet() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 200 ether); // short of 300

        vm.prank(alice);
        vm.expectRevert(TownCharity.NotFunded.selector);
        charity.submitEvidence(id, 0, keccak256("photos"));
    }

    /* --------------------------------------------------------------------- refunds */

    function test_MissedDeadlineRefundsEveryDonorInFull() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 120 ether);
        vm.prank(carol);
        charity.pledge(id, 30 ether);

        uint256 bobStart = token.balanceOf(bob);
        uint256 carolStart = token.balanceOf(carol);

        vm.warp(block.timestamp + WINDOW + 1);
        charity.closeFailed(id); // anyone may call this — here, nobody involved
        assertEq(uint8(charity.get(id).state), uint8(TownCharity.State.Failed));

        vm.prank(bob);
        charity.refund(id);
        vm.prank(carol);
        charity.refund(id);

        assertEq(token.balanceOf(bob), bobStart + 120 ether);
        assertEq(token.balanceOf(carol), carolStart + 30 ether);
        assertEq(token.balanceOf(address(charity)), 0);
    }

    function test_CannotCloseBeforeTheDeadline() public {
        uint256 id = _campaign();
        vm.expectRevert(TownCharity.TooEarly.selector);
        charity.closeFailed(id);
    }

    function test_RejectedMilestoneReturnsTheUnspentRemainderProRata() public {
        uint256 id = _campaign();
        _fund(id); // bob 200, carol 100, goal 300

        vm.prank(alice);
        charity.submitEvidence(id, 0, keccak256("photos of the hole"));
        vm.prank(townAdmin);
        charity.approveMilestone(id, 0); // 100 paid, 200 left

        vm.prank(alice);
        charity.submitEvidence(id, 1, keccak256("a photo of someone else's pump"));
        vm.prank(townAdmin);
        charity.rejectMilestone(id, 1, "the pump is not installed");

        assertEq(uint8(charity.get(id).state), uint8(TownCharity.State.Cancelled));

        uint256 bobStart = token.balanceOf(bob);
        uint256 carolStart = token.balanceOf(carol);

        vm.prank(bob);
        charity.refund(id);
        vm.prank(carol);
        charity.refund(id);

        // Two thirds of 200 to bob, one third to carol — the approved tranche stays paid.
        assertEq(token.balanceOf(bob) - bobStart, 133333333333333333333);
        assertEq(token.balanceOf(carol) - carolStart, 66666666666666666666);
        assertLe(token.balanceOf(address(charity)), 2, "only rounding dust may remain");
    }

    function test_RefundCannotBeTakenTwice() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 50 ether);
        vm.warp(block.timestamp + WINDOW + 1);
        charity.closeFailed(id);

        vm.prank(bob);
        charity.refund(id);
        vm.prank(bob);
        vm.expectRevert(TownCharity.AlreadyRefunded.selector);
        charity.refund(id);
    }

    function test_NonDonorGetsNothingBack() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 50 ether);
        vm.warp(block.timestamp + WINDOW + 1);
        charity.closeFailed(id);

        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(TownCharity.NothingToRefund.selector);
        charity.refund(id);
    }

    function test_ASuccessfulCampaignRefundsNobody() public {
        uint256 id = _campaign();
        _fund(id);
        vm.prank(bob);
        vm.expectRevert(TownCharity.NotRaising.selector);
        charity.refund(id);
    }

    /* ------------------------------------------------------------ setting one up */

    function test_MilestonesMustAddUpToTheGoal() public {
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 100 ether; // 200, not 300
        string[] memory what = new string[](2);
        what[0] = "Dig";
        what[1] = "Pump";

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(TownCharity.MilestonesDoNotSumToGoal.selector, 200 ether, GOAL)
        );
        charity.create("A well", GOAL, WINDOW, amounts, what);
    }

    function test_OneMilestoneIsNotMilestoneFunding() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = GOAL;
        string[] memory what = new string[](1);
        what[0] = "Everything";

        vm.prank(alice);
        vm.expectRevert(TownCharity.BadMilestones.selector);
        charity.create("A well", GOAL, WINDOW, amounts, what);
    }

    function test_PledgeCannotExceedWhatIsStillNeeded() public {
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, 250 ether);

        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(TownCharity.Overfunded.selector, 50 ether));
        charity.pledge(id, 60 ether);
    }

    function test_PledgingClosesAtTheDeadline() public {
        uint256 id = _campaign();
        vm.warp(block.timestamp + WINDOW);
        vm.prank(bob);
        vm.expectRevert(TownCharity.NotRaising.selector);
        charity.pledge(id, 1 ether);
    }

    /* ----------------------------------------------------------------------- fuzz */

    /// However the pledges fall, a failed campaign never pays a donor more than they gave,
    /// and never keeps any of it.
    function testFuzz_FailedCampaignReturnsExactlyWhatWasGiven(uint96 a, uint96 b) public {
        uint256 pledgeA = bound(uint256(a), 1, 299 ether);
        uint256 pledgeB = bound(uint256(b), 1, 299 ether - pledgeA + 1);
        vm.assume(pledgeA + pledgeB < GOAL);

        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, pledgeA);
        vm.prank(carol);
        charity.pledge(id, pledgeB);

        uint256 bobStart = token.balanceOf(bob);
        uint256 carolStart = token.balanceOf(carol);

        vm.warp(block.timestamp + WINDOW + 1);
        charity.closeFailed(id);

        vm.prank(bob);
        charity.refund(id);
        vm.prank(carol);
        charity.refund(id);

        assertEq(token.balanceOf(bob) - bobStart, pledgeA);
        assertEq(token.balanceOf(carol) - carolStart, pledgeB);
        assertEq(token.balanceOf(address(charity)), 0);
    }

    /// The contract can never pay out more than it took in, whatever the split.
    function testFuzz_RefundsPlusReleasesNeverExceedTheGoal(uint96 split) public {
        uint256 bobShare = bound(uint256(split), 1 ether, GOAL - 1 ether);
        uint256 id = _campaign();
        vm.prank(bob);
        charity.pledge(id, bobShare);
        vm.prank(carol);
        charity.pledge(id, GOAL - bobShare);

        vm.prank(alice);
        charity.submitEvidence(id, 0, keccak256("photos"));
        vm.prank(townAdmin);
        charity.approveMilestone(id, 0);
        vm.prank(alice);
        charity.submitEvidence(id, 1, keccak256("photos"));
        vm.prank(townAdmin);
        charity.rejectMilestone(id, 1, "no");

        vm.prank(bob);
        charity.refund(id);
        vm.prank(carol);
        charity.refund(id);

        assertLe(token.balanceOf(address(charity)), 2, "at most rounding dust stays");
    }
}
