# Module 15 · Swapping, lending, and a price you can lie about

> This module ships a contract with a **deliberate vulnerability**, a test that exploits it
> successfully, and an exercise to fix it. Nothing here should be copied into anything that
> holds real value. That is the point: the bug is the lesson.

## The problem

Trustville has one currency and no market. A farmer holding GRAIN who owes TVD has to find
somebody who wants exactly what they have, at the moment they have it — and a farmer who
needs cash before harvest has to find somebody willing to lend it.

Both are matching problems, and both are usually solved by an institution: an exchange with
an order book, a bank with a credit department. This module replaces each with a formula,
and then shows what that substitution costs.

## Part one: the market

### Why an AMM

A constant-product pool holds both assets and obeys

```
x · y = k
```

It will trade with anybody, at any hour, without a counterparty on the other side. Take
GRAIN out and GRAIN becomes scarcer in the pool, so the next unit costs more. **Nobody sets
the price. The ratio of the reserves is the price.**

A database could run an order book perfectly well — in fact it would run one far better and
cheaper. What it could not do is let anyone trade without asking permission, or let anyone
verify that the operator is not trading against them. That is the trade this design buys,
and it buys it at a cost in efficiency that is worth being honest about.

### Three things that follow from the curve

**Slippage is not a fee.** The price you saw is the price of an infinitely small trade. A
500 TVD order into a 1000 TVD pool gets around 333 GRAIN, not 500 — the rate got worse as
the order consumed the pool. `quote()` tells you the real number before you sign; `minOut`
is how you refuse a worse one.

**Fees go to the providers.** 0.3% of every input stays in the pool and no new shares are
printed, so each existing share is worth slightly more. `k` only ever grows, and a test
asserts it.

**Providing liquidity is a position, not a deposit.** The pool automatically sells whichever
asset is rising. Come back after a big move and you hold more of the loser and less of the
winner. `test_ImpermanentLossIsRealAndMeasurable` puts a number on it: Alice provides 1000
of each at 1:1, one large trade moves the price, and she withdraws worth less than if she
had simply held — *after* collecting every fee from that trade. Students are usually told
liquidity provision is yield. It is a short-volatility position with a fee attached.

### What GRAIN is for

A price is a ratio between two things, so a second asset is the smallest change that makes
prices, lending and liquidation mean anything at all.

GRAIN has no mint function. `harvest()` is the only door: any resident, a fixed amount, once
per cooldown — the same rule for the town admin as for everyone else. That is the same
pattern as the Bank in module 3, and worth pointing at again, because "who can create this
asset" is the first question to ask of any token.

## Part two: the loan, and the bug

### Why over-collateralised

The contract cannot sue you. There is no identity behind a borrower, no court, no
collections department. The only enforcement available is collateral worth more than the
loan, so you deposit 200 GRAIN to borrow 100 TVD.

This is why on-chain lending looks nothing like a mortgage, and it is a genuine limitation
rather than a design preference: the useful thing about credit is lending to people who do
not already have the money.

| Number | Value | Why |
| --- | --- | --- |
| Loan-to-value | 50% | Room for the price to move before the loan is in danger |
| Liquidation threshold | 70% | Past this, anyone may close the position |
| Liquidation bonus | 10% | Somebody must be paid to spend gas cleaning up a loss |

The bonus is not generosity. Without it, nobody closes bad positions and the bad debt just
sits there getting worse.

### The bug

`GrainLoans` values collateral with `TownSwap.unsafeSpotTvdPerGrain()` — the pool's reserves
at the instant of the call. **The reserves are exactly what a trader can change.**

`test_ATTACK_InflateTheCollateralPriceAndWalkAway` runs the whole thing in one transaction:

| Step | What happens | Price |
| --- | --- | --- |
| start | attacker holds 600 GRAIN, honestly worth ~600 TVD | 1.00 |
| 1 | swaps 900 TVD into the pool — GRAIN becomes scarce | **3.60** |
| 2 | deposits 600 GRAIN, borrows 1081 TVD at 50% of the invented valuation | 3.60 |
| 3 | sells the GRAIN back; the price returns | 1.00 |
| end | keeps 1078 TVD net, abandons collateral worth 602 | |

The loan is left at 1081 TVD of debt against 602 TVD of collateral. A second test confirms
the position cannot be liquidated without a loss: seizing every grain of it does not cover
the debt, so the lenders eat the difference.

Nothing in the attack is exotic. No reentrancy, no compiler quirk, no leaked key. Every
call is a function working exactly as written. **The vulnerability is a belief** — that a
number which happens to be called a price is one.

This is the shape of most real DeFi losses. It is worth saying to students plainly: the
exploits that take the money are usually not clever code, they are a wrong assumption about
where a number came from.

### Finding it yourself

Before reading the test, give students the contract and this question: *the lending pool
lost money and no function reverted. Where did the number come from?* Working back from
"someone borrowed more than their collateral was worth" to "the price is a storage slot
anybody can write to" is the exercise, and it transfers far better than being told.

### Three fixes, and what each costs

| Fix | How | The cost |
| --- | --- | --- |
| **Time-weighted average price** | Accumulate price × time in the pool; read the average over a window | The price now lags. In a genuine fast crash, liquidations fire late and the pool still loses — you have traded manipulation risk for staleness risk |
| **An independent oracle** | Reuse module 14's M-of-N median for a price feed | You are no longer trusting a pool, you are trusting reporters. Same trade in a different coat — and now you must keep them honest and alive |
| **Both, and take the worse** | Price at min(TWAP, oracle) for collateral, max for debt | Most robust, most gas, most code. What large protocols actually do |

There is no fourth option where the problem disappears. Every design picks which failure it
prefers, and a student who can say which one their design chose has learned the module.

## Try it

1. **Harvest** some GRAIN, then try again immediately — the cooldown refuses you.
2. **Seed the pool** with equal amounts and note that you have just set the price.
3. **Quote a small trade, then a large one.** Compare the rate. That gap is slippage.
4. **Swap with a tight `minOut`** while someone else trades first. Yours fails, which is
   what `minOut` is for.
5. **Provide liquidity, have someone make a big trade, then withdraw.** Count what you
   have against what you would have had by holding.
6. **Borrow properly:** deposit 200 GRAIN, borrow 100 TVD, watch the health factor.
7. **Make a price fall honestly** — have somebody sell a lot of GRAIN — and liquidate the
   position. Notice the liquidator is paid to do it.
8. **Then run the attack** with a throwaway account and watch the pool lose money while
   every transaction succeeds.

## Extend it

1. Implement the TWAP and re-run the attack test. It should now fail — and write a *new*
   test showing what the TWAP costs you during a genuine fast move.
2. Replace the spot price with a module 14 style price oracle. Then answer: who runs the
   reporters, and what stops them borrowing against their own quote?
3. Add a borrowing rate that rises with utilisation, so the pool prices its own scarcity.
4. Replace lazy interest with a global index, so a position nobody touches still accrues
   into `totalDebt`.
5. Cap each position's size relative to pool depth, and argue about whether that is a fix
   or a delay.

## Security checklist

- [ ] Where does every price in this system come from, and who can change it?
- [ ] Can a price used for a decision be moved within the same transaction as the decision?
- [ ] Can a borrower withdraw collateral that is holding up a loan?
- [ ] Can a lender withdraw cash that is currently lent out? Should they be able to?
- [ ] Is the liquidation bonus large enough to pay for gas, and small enough not to invite
      liquidations that do not need to happen?
- [ ] What happens when collateral is worth less than the debt? Who absorbs it?
- [ ] Does `k` ever decrease? Under what rounding?
- [ ] If the pool is nearly empty, what does the first deposit after that let somebody do?
