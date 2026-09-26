// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GrainToken} from "../src/GrainToken.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownSwap} from "../src/TownSwap.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Reading a role off a contract is an external call, and one in the argument list of a
/// pranked call consumes the prank. Hoist every such read to a local first.
contract SwapTest is Test {
    bytes32 constant ADMIN = 0x00;
    uint64 constant COOLDOWN = 1 minutes;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken tvd;
    TownBank bank;
    GrainToken grain;
    TownSwap swap;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address alice = makeAddr("alice"); // liquidity provider
    address bob = makeAddr("bob"); // trader
    address carol = makeAddr("carol"); // second trader

    function setUp() public {
        vm.warp(1_000_000);

        vm.startPrank(deployer);
        registry = new ResidentRegistry(deployer);
        passport = new TrustvillePassport(deployer, registry);
        tvd = new TownToken(deployer, 10_000_000 ether);
        bank = new TownBank(deployer, registry, tvd, passport, 1000 ether);
        tvd.grantRole(tvd.MINTER_ROLE(), address(bank));
        passport.grantRole(passport.STAMPER_ROLE(), address(bank));
        registry.grantRole(registry.REGISTRAR_ROLE(), townAdmin);
        _handOver(address(registry));
        _handOver(address(passport));
        _handOver(address(tvd));
        _handOver(address(bank));
        registry.renounceRole(registry.REGISTRAR_ROLE(), deployer);

        grain = new GrainToken(townAdmin, registry, COOLDOWN);
        swap = new TownSwap(IERC20(address(tvd)), IERC20(address(grain)), passport);
        vm.stopPrank();

        bytes32 stamper = passport.STAMPER_ROLE();
        vm.prank(townAdmin);
        passport.grantRole(stamper, address(swap));

        for (uint256 i; i < 3; i++) {
            address who = [alice, bob, carol][i];
            vm.startPrank(who);
            registry.register(keccak256(abi.encodePacked(who)));
            passport.mint();
            bank.claimWelcomeGrant();
            tvd.approve(address(swap), type(uint256).max);
            grain.approve(address(swap), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    /// Harvest `times` lots of 100 GRAIN, waiting out the cooldown between each.
    function _farm(address who, uint256 times) internal {
        for (uint256 i; i < times; i++) {
            vm.prank(who);
            grain.harvest();
            vm.warp(block.timestamp + COOLDOWN + 1);
        }
    }

    /// A 1000 / 1000 pool: one GRAIN is worth one TVD, because that is what was put in.
    function _pool() internal {
        _farm(alice, 10);
        vm.prank(alice);
        swap.addLiquidity(1000 ether, 1000 ether, 0);
    }

    /* ==================================================================== the grain */

    function test_HarvestIsRateLimitedNotGated() public {
        vm.prank(bob);
        grain.harvest();
        assertEq(grain.balanceOf(bob), 100 ether);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(GrainToken.TooSoon.selector, uint64(block.timestamp) + COOLDOWN)
        );
        grain.harvest();

        vm.warp(block.timestamp + COOLDOWN + 1);
        vm.prank(bob);
        grain.harvest();
        assertEq(grain.balanceOf(bob), 200 ether);
    }

    function test_OnlyResidentsHarvest() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(GrainToken.NotAResident.selector);
        grain.harvest();
    }

    function test_NobodyCanMintGrain() public {
        // There is no mint function at all — harvest is the only door, and it has the same
        // rules for the admin as for everyone else.
        vm.prank(townAdmin);
        vm.expectRevert(GrainToken.NotAResident.selector);
        grain.harvest();
    }

    /* ===================================================================== the pool */

    function test_TheFirstDepositSetsThePrice() public {
        _pool();
        assertEq(swap.reserveTvd(), 1000 ether);
        assertEq(swap.reserveGrain(), 1000 ether);
        assertEq(swap.unsafeSpotTvdPerGrain(), 1 ether, "one for one, because that went in");
        assertGt(swap.sharesOf(alice), 0);
    }

    function test_LaterDepositsMustMatchTheCurrentRatio() public {
        _pool();
        _farm(bob, 1);

        // The pool is 1:1, so 50 TVD needs 50 GRAIN. Offering only 10 is refused, and the
        // error says what it actually wanted.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TownSwap.WrongRatio.selector, 50 ether));
        swap.addLiquidity(50 ether, 10 ether, 0);
    }

    function test_SwappingMovesThePriceAndGrowsK() public {
        _pool();
        uint256 kBefore = swap.k();

        vm.prank(bob);
        swap.swapTvdForGrain(100 ether, 0, 0);

        assertGt(swap.unsafeSpotTvdPerGrain(), 1 ether, "GRAIN is scarcer, so it costs more");
        assertGt(swap.k(), kBefore, "k only ever grows - that growth is the fee");
        assertTrue(passport.hasStamp(bob, 15));
    }

    /// The headline price is the price of an infinitely small trade. Yours is worse, and
    /// the bigger it is the worse it gets. This is the curve, not a fee.
    function test_BiggerTradesGetWorsePrices() public {
        _pool();

        uint256 smallOut = swap.quote(1 ether, true);
        uint256 bigOut = swap.quote(500 ether, true);

        // 500x the input buys nowhere near 500x the output.
        assertLt(bigOut, smallOut * 500, "slippage");
        assertLt(bigOut, 340 ether, "a 500 TVD order into a 1000 pool gets about 333 GRAIN");
    }

    function test_QuoteMatchesWhatYouActuallyGet() public {
        _pool();
        uint256 expected = swap.quote(100 ether, true);

        uint256 before = grain.balanceOf(bob);
        vm.prank(bob);
        swap.swapTvdForGrain(100 ether, 0, 0);
        assertEq(grain.balanceOf(bob) - before, expected, "no surprises between quoting and signing");
    }

    function test_MinOutRefusesAWorsePrice() public {
        _pool();
        uint256 expected = swap.quote(100 ether, true);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(TownSwap.TooLittleOut.selector, expected, expected + 1)
        );
        swap.swapTvdForGrain(100 ether, expected + 1, 0);
    }

    /// The protection students forget: someone else's trade lands first, the price moves,
    /// and minOut is what stops you eating it.
    function test_MinOutProtectsAgainstBeingFrontRun() public {
        _pool();
        uint256 expected = swap.quote(100 ether, true);

        vm.prank(carol);
        swap.swapTvdForGrain(300 ether, 0, 0); // carol gets there first

        vm.prank(bob);
        vm.expectRevert();
        swap.swapTvdForGrain(100 ether, expected, 0); // bob's order at the old price fails
    }

    function test_DeadlineExpires() public {
        _pool();
        vm.prank(bob);
        vm.expectRevert(TownSwap.Expired.selector);
        swap.swapTvdForGrain(1 ether, 0, block.timestamp - 1);
    }

    /* ============================================================ being the market */

    function test_FeesMakeEachShareWorthMore() public {
        _pool();
        uint256 shares = swap.sharesOf(alice);
        uint256 kBefore = swap.k();

        _farm(bob, 3);
        for (uint256 i; i < 3; i++) {
            vm.prank(bob);
            swap.swapTvdForGrain(50 ether, 0, 0);
            vm.prank(bob);
            swap.swapGrainForTvd(40 ether, 0, 0);
        }

        assertGt(swap.k(), kBefore, "every round trip leaves fees behind");
        assertEq(swap.sharesOf(alice), shares, "and no new shares were printed for them");
    }

    /// Impermanent loss, measured. Alice puts in 1000 of each at 1:1. A large one-way trade
    /// moves the price. She withdraws — and is worse off than if she had simply held, even
    /// after collecting every fee.
    function test_ImpermanentLossIsRealAndMeasurable() public {
        _pool();

        _farm(bob, 1);
        vm.prank(bob);
        swap.swapTvdForGrain(500 ether, 0, 0);

        uint256 price = swap.unsafeSpotTvdPerGrain(); // TVD per GRAIN, now well above 1

        uint256 shares = swap.sharesOf(alice);
        vm.prank(alice);
        (uint256 outTvd, uint256 outGrain) = swap.removeLiquidity(shares, 0);

        uint256 asProvider = outTvd + (outGrain * price) / 1e18;
        uint256 asHolder = 1000 ether + (1000 ether * price) / 1e18;

        assertLt(asProvider, asHolder, "providing liquidity sold the winner on the way up");
        assertGt(outTvd, 1000 ether, "she holds more of the asset that fell");
        assertLt(outGrain, 1000 ether, "and less of the one that rose");
    }

    function test_WithdrawingTakesTodaysReservesNotYesterdaysDeposit() public {
        _pool();
        _farm(bob, 1);
        vm.prank(bob);
        swap.swapGrainForTvd(100 ether, 0, 0);

        uint256 shares = swap.sharesOf(alice);
        vm.prank(alice);
        (uint256 outTvd, uint256 outGrain) = swap.removeLiquidity(shares, 0);

        assertLt(outTvd, 1000 ether);
        assertGt(outGrain, 1000 ether);
        assertEq(swap.sharesOf(alice), 0);
    }

    function test_CannotWithdrawSharesYouDoNotHave() public {
        _pool();
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(TownSwap.NotEnoughShares.selector, 0, 1));
        swap.removeLiquidity(1, 0);
    }

    /* ----------------------------------------------------------------------- fuzz */

    /// Whatever anyone trades, the pool never loses value: k after is never less than k
    /// before. That single invariant is what stops the pool being drained.
    function testFuzz_KNeverShrinks(uint96 amount, bool tvdIn) public {
        _pool();
        uint256 size = bound(uint256(amount), 0.001 ether, 500 ether);
        uint256 kBefore = swap.k();

        if (tvdIn) {
            vm.prank(bob);
            swap.swapTvdForGrain(size, 0, 0);
        } else {
            _farm(bob, 6); // enough GRAIN to sell
            vm.prank(bob);
            swap.swapGrainForTvd(size > 600 ether ? 600 ether : size, 0, 0);
        }

        assertGe(swap.k(), kBefore);
    }
}
