// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownGovernor} from "../src/TownGovernor.sol";
import {TownTimelock} from "../src/TownTimelock.sol";
import {TownToken} from "../src/TownToken.sol";
import {TownTreasury} from "../src/TownTreasury.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";
import {VoteToken} from "../src/VoteToken.sol";

contract CouncilTest is Test {
    bytes32 constant ADMIN = 0x00;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken token;
    TownBank bank;
    VoteToken votes;
    TownTimelock timelock;
    TownGovernor governor;
    TownTreasury treasury;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address ana = makeAddr("ana");
    address ben = makeAddr("ben");
    address cleo = makeAddr("cleo");
    address builder = makeAddr("builder"); // gets paid by proposals

    uint48 constant VOTING_DELAY = 60; // seconds
    uint32 constant VOTING_PERIOD = 600;
    uint256 constant TIMELOCK_DELAY = 120;

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

        votes = new VoteToken(IERC20(address(token)));

        address[] memory none = new address[](0);
        timelock = new TownTimelock(TIMELOCK_DELAY, none, none, deployer);
        governor = new TownGovernor(IVotes(address(votes)), timelock, VOTING_DELAY, VOTING_PERIOD, 0);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0)); // anyone may execute
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        address[] memory owners = new address[](3);
        owners[0] = ana;
        owners[1] = ben;
        owners[2] = cleo;
        treasury = new TownTreasury(owners, 2, passport);
        vm.stopPrank();

        vm.startPrank(townAdmin);
        passport.grantRole(passport.STAMPER_ROLE(), address(treasury));
        vm.stopPrank();

        for (uint256 i; i < 3; i++) {
            address who = [ana, ben, cleo][i];
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

    function _wrap(address who, uint256 amount) internal {
        vm.startPrank(who);
        token.approve(address(votes), amount);
        votes.depositAndSelfDelegate(amount);
        vm.stopPrank();
    }

    /* ------------------------------------------------------------ module 11 */

    function test_MultisigNeedsTwoOfThree() public {
        vm.prank(ana);
        token.transfer(address(treasury), 300 ether); // fund it

        bytes memory data = treasury.encodeTransfer(builder, 100 ether);
        vm.prank(ana);
        uint256 id = treasury.propose(address(token), 0, data, "pay the builder");
        assertEq(treasury.get(id).confirmations, 1); // proposing confirms

        vm.expectRevert(abi.encodeWithSelector(TownTreasury.NotEnoughConfirmations.selector, uint32(1), 2));
        treasury.execute(id);

        vm.prank(ben);
        treasury.confirm(id);

        uint256 before = token.balanceOf(builder);
        treasury.execute(id); // anyone may push the button
        assertEq(token.balanceOf(builder), before + 100 ether);
        assertTrue(treasury.get(id).executed);
    }

    function test_NonOwnerCannotProposeOrConfirm() public {
        vm.prank(builder);
        vm.expectRevert(TownTreasury.NotAnOwner.selector);
        treasury.propose(address(token), 0, "", "sneaky");
    }

    function test_ConfirmationCanBeRevokedBeforeExecution() public {
        bytes memory data = treasury.encodeTransfer(builder, 1 ether); // encode BEFORE pranking
        vm.prank(ana);
        uint256 id = treasury.propose(address(token), 0, data, "maybe");
        vm.prank(ben);
        treasury.confirm(id);
        assertEq(treasury.get(id).confirmations, 2);

        vm.prank(ben);
        treasury.revokeConfirmation(id);
        assertEq(treasury.get(id).confirmations, 1);

        vm.expectRevert(abi.encodeWithSelector(TownTreasury.NotEnoughConfirmations.selector, uint32(1), 2));
        treasury.execute(id);
    }

    function test_CannotExecuteTwice() public {
        bytes memory data = treasury.encodeTransfer(builder, 5 ether);
        vm.prank(ana);
        token.transfer(address(treasury), 10 ether);
        vm.prank(ana);
        uint256 id = treasury.propose(address(token), 0, data, "once");
        vm.prank(ben);
        treasury.confirm(id);
        treasury.execute(id);

        vm.expectRevert(TownTreasury.AlreadyExecuted.selector);
        treasury.execute(id);
    }

    function test_OwnersCanOnlyChangeThroughTheMultisig() public {
        vm.prank(ana);
        vm.expectRevert(TownTreasury.NotTheTreasury.selector);
        treasury.addOwner(builder);

        // the legitimate route: a payment whose target is the treasury itself
        bytes memory data = abi.encodeWithSignature("addOwner(address)", builder);
        vm.prank(ana);
        uint256 id = treasury.propose(address(treasury), 0, data, "add the builder as a signer");
        vm.prank(cleo);
        treasury.confirm(id);
        treasury.execute(id);

        assertTrue(treasury.isOwner(builder));
        assertEq(treasury.ownerCount(), 4);
    }

    function test_FailedCallRevertsTheWholeExecution() public {
        // treasury holds nothing, so the transfer fails
        bytes memory data = treasury.encodeTransfer(builder, 1 ether);
        vm.prank(ana);
        uint256 id = treasury.propose(address(token), 0, data, "broke");
        vm.prank(ben);
        treasury.confirm(id);

        vm.expectRevert();
        treasury.execute(id);
        assertFalse(treasury.get(id).executed); // still open, not silently consumed
    }

    /* ------------------------------------------------------------ module 12 */

    function _fundTimelock(uint256 amount) internal {
        vm.prank(ana);
        token.transfer(address(timelock), amount);
    }

    function _proposePayment(address who, uint256 amount, string memory description)
        internal
        returns (uint256 id, address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(token);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("transfer(address,uint256)", builder, amount);

        vm.prank(who);
        id = governor.propose(targets, values, calldatas, description);
    }

    function test_FullCycle_ProposeVoteQueueExecute() public {
        _fundTimelock(300 ether);
        _wrap(ana, 600 ether); // ana: 1000 grant - 300 sent = 700 left
        _wrap(ben, 400 ether);

        (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c) =
            _proposePayment(ana, 250 ether, "pay the builder for the bridge");
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Pending));
        assertEq(governor.proposalCount(), 1);

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Active));

        vm.prank(ana);
        governor.castVote(id, 1); // for
        vm.prank(ben);
        governor.castVote(id, 0); // against

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        bytes32 descHash = keccak256(bytes("pay the builder for the bridge"));
        governor.queue(t, v, c, descHash);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Queued));

        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        uint256 before = token.balanceOf(builder);
        governor.execute(t, v, c, descHash); // anyone may execute
        assertEq(token.balanceOf(builder), before + 250 ether);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Executed));
    }

    function test_CannotExecuteBeforeTheTimelockMatures() public {
        _fundTimelock(100 ether);
        _wrap(ana, 500 ether);
        (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c) =
            _proposePayment(ana, 50 ether, "too fast");

        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(ana);
        governor.castVote(id, 1);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        governor.queue(t, v, c, keccak256(bytes("too fast")));

        vm.expectRevert(); // the waiting period is the safeguard
        governor.execute(t, v, c, keccak256(bytes("too fast")));
    }

    function test_WrappedButNotDelegatedCannotDecideAnything() public {
        _fundTimelock(100 ether);

        vm.startPrank(ana); // wraps, never delegates
        token.approve(address(votes), 900 ether);
        votes.depositFor(ana, 900 ether);
        vm.stopPrank();
        _wrap(ben, 100 ether); // small but delegated

        (uint256 id,,,) = _proposePayment(ben, 10 ether, "quiet whale");
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.prank(ana);
        governor.castVote(id, 0); // against, with 900 tokens held
        vm.prank(ben);
        governor.castVote(id, 1); // for, with 100 delegated

        (uint256 against, uint256 forVotes,) = governor.proposalVotes(id);
        assertEq(against, 0); // the whale's tokens counted for nobody
        assertEq(forVotes, 100 ether);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Succeeded));
    }

    function test_BuyingTokensAfterTheSnapshotDoesNotHelp() public {
        _fundTimelock(100 ether);
        _wrap(ana, 200 ether);

        (uint256 id,,,) = _proposePayment(ana, 10 ether, "late whale");
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        _wrap(cleo, 900 ether); // wraps and delegates only AFTER the snapshot
        vm.prank(cleo);
        governor.castVote(id, 0);

        (uint256 against,,) = governor.proposalVotes(id);
        assertEq(against, 0); // power is measured at the snapshot, not now
    }

    function test_DefeatedProposalCannotBeQueued() public {
        _fundTimelock(100 ether);
        _wrap(ana, 100 ether);
        _wrap(ben, 500 ether);

        (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c) =
            _proposePayment(ana, 50 ether, "unpopular");
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(ana);
        governor.castVote(id, 1);
        vm.prank(ben);
        governor.castVote(id, 0);
        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
        vm.expectRevert();
        governor.queue(t, v, c, keccak256(bytes("unpopular")));
    }

    function test_QuorumMustBeReached() public {
        _fundTimelock(100 ether);
        // wrapped supply = 2400, so quorum (4%) = 96
        _wrap(ana, 800 ether);
        _wrap(ben, 800 ether);
        _wrap(cleo, 800 ether);

        // one small voter, delegated BEFORE the proposal so the snapshot sees them
        address quiet = makeAddr("quiet");
        vm.prank(cleo);
        votes.transfer(quiet, 50 ether);
        vm.prank(quiet);
        votes.delegate(quiet);

        (uint256 id,,,) = _proposePayment(ana, 10 ether, "nobody turned up");
        vm.warp(block.timestamp + VOTING_DELAY + 1);

        vm.prank(quiet);
        governor.castVote(id, 1); // 50 votes for, unopposed

        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        // unopposed, but 50 < 96: a vote nobody attends does not pass
        assertEq(governor.quorum(governor.proposalSnapshot(id)), 96 ether);
        assertEq(uint8(governor.state(id)), uint8(IGovernor.ProposalState.Defeated));
    }

    function test_TimelockIsOwnedByNobody() public view {
        assertTrue(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)));
        assertTrue(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), townAdmin));
    }

    function test_NobodyCanSpendTheTimelockDirectly() public {
        _fundTimelock(100 ether);
        vm.prank(townAdmin); // not even the town admin
        vm.expectRevert();
        timelock.schedule(address(token), 0, "", bytes32(0), bytes32(0), TIMELOCK_DELAY);
    }
}
