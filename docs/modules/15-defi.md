# Module 15 · Swap and lending

| | |
| --- | --- |
| **Contracts** | `GrainToken.sol`, `TownSwap.sol`, `GrainLoans.sol` |
| **Stop** | Exchange |
| **Patterns** | Constant-product AMM; over-collateralised lending |
| **Stamp** | Module 15 (on a swap, and on a borrow) |

> ⚠ **`GrainLoans` contains a deliberate vulnerability.** It is the point of the module. Do
> not copy it into anything real, and read the attack section before you read anything else.

## The problem

Two problems, and the second only exists because of how we solve the first.

**Exchange.** A farmer has GRAIN and wants TVD. An order book needs a matched counterparty
at a matched price at a matched moment, and on a small market that counterparty is usually
not there.

**Credit.** A farmer with GRAIN wants TVD without selling — the harvest is next month, the
bill is today. Lending needs collateral, and collateral needs a **price**.

Where does a smart contract get a price?

## The idea

**An AMM.** No order book, no counterparty — a pool holding both tokens and a formula.
`x · y = k`: the product of the reserves never falls. Put TVD in, the formula says how much
GRAIN comes out. Anyone can trade at any size at any time, and the price is whatever the
reserves say it is.

**Over-collateralised lending.** Deposit GRAIN, borrow up to 50% of its value in TVD. Debt
above 70% and anyone may liquidate you, paying off part of your debt and taking collateral
plus a 10% bonus.

And the trap: **the lending contract reads the AMM's spot price.** It is the obvious source
— it is on chain, it is free, it is right there. It is also the thing the borrower can move.

## Key terms

**AMM.** Automated market maker: a contract that quotes both sides from a formula over its
reserves.

**Constant product.** `reserveIn · reserveOut = k`, Uniswap V2's invariant. `k` only grows,
by the fees.

**Slippage.** Your trade moves the price against you. Big trades in small pools get bad
fills — not a bug, arithmetic.

**Liquidity provider.** Someone who deposits both tokens and earns a share of fees. They
carry impermanent loss.

**LTV / liquidation threshold / bonus.** 5000 / 7000 / 1000 basis points here: borrow up to
50%, liquidatable at 70%, liquidator takes a 10% premium.

**Health factor.** Below 1e18 means liquidatable. The number a borrower watches.

**Spot price.** The price implied by reserves *right now*. **Not a price feed.** This
distinction is the whole module.

**Oracle manipulation.** Moving the price a contract reads, in order to extract value from
whatever decision it makes on it.

## How it works

**GRAIN** is an ERC-20 with no mint function. Residents call `harvest()` for 100 GRAIN,
rate-limited by a cooldown. No admin can print it.

**TownSwap**

```solidity
uint256 inAfterFee = amountIn * (10_000 - FEE_BPS);          // FEE_BPS = 30 → 0.3%
return (inAfterFee * reserveOut) / (reserveIn * 10_000 + inAfterFee);
```

| Function | What |
| --- | --- |
| `addLiquidity(amountTvd, maxGrain, deadline)` | Deposit both at the current ratio; receive shares |
| `removeLiquidity(shares, deadline)` | Take your share of both |
| `swapTvdForGrain(amountIn, minOut, deadline)` | `minOut` is your slippage protection |
| `swapGrainForTvd(amountIn, minOut, deadline)` | The other direction |
| `quote(amountIn, tvdIn)` | What this **specific** trade returns |
| `unsafeSpotTvdPerGrain()` | The price — note the name |
| `k()` | The invariant |

**GrainLoans**

| Function | What |
| --- | --- |
| `supply(amount)` / `withdrawSupply(shares)` | Lenders provide TVD, earn interest |
| `depositCollateral` / `withdrawCollateral` | GRAIN in and out |
| `borrow(amount)` | Up to `LTV_BPS` of collateral value |
| `repay(amount)` | Interest first, folded into debt on every touch |
| `liquidate(borrower, repayAmount)` | Anyone, above the threshold, for a bonus |
| `healthFactor(who)` | Below 1e18 → liquidatable |

## The detail that matters

### The bug

```solidity
/// @dev HERE IS THE BUG. The spot price of an AMM is not a price feed: it is a
///      snapshot of one pool's reserves, and reserves are exactly what a trader can change.
function _valueOf(uint256 grainAmount) private view returns (uint256) {
    return (grainAmount * swap.unsafeSpotTvdPerGrain()) / 1e18;
}
```

One line. It reads a number from a pool, and that number is a function of reserves that
anyone with capital can move inside a single transaction.

The attack, which the repository performs in `test_ATTACK_InflateTheCollateralPriceAndWalkAway`:

1. **Pump.** Swap a large amount of TVD for GRAIN. The pool's TVD reserve rises, its GRAIN
   reserve falls, and `unsafeSpotTvdPerGrain` rises with them. In the test the price goes
   from **1.00 to 3.605 TVD per GRAIN**.
2. **Borrow.** Deposit GRAIN as collateral. The lender values it at the inflated price and
   lets you borrow **1081.46 TVD** against collateral genuinely worth **601.71**.
3. **Dump.** Swap the GRAIN back. The price falls to **1.0028** — near where it started.
4. **Walk.** The debt stays. Your position is deeply underwater and you do not care, because
   you are up **1078.6 TVD** and the collateral you abandon is worth less than what you took.

The loss lands on the lenders who supplied the TVD.

Nothing here is exotic. No reentrancy, no overflow, no compiler quirk, no admin key. Every
call is a documented function used exactly as intended. **The contract is correct and the
system is broken**, and that gap is the most valuable thing in this module — most real
losses look like this, not like a clever exploit.

Run it and watch the numbers:

```bash
cd contracts && forge test --match-test test_ATTACK -vvv
```

### Why the fix is not obvious

- **"Use a TWAP."** A time-weighted average over, say, thirty minutes makes the attack cost
  far more — you must hold the price up for the whole window, exposed to arbitrageurs the
  entire time. It does not make it impossible, and it makes liquidations lag reality, which
  is its own risk in a crash.
- **"Use an oracle."** Now you have module 14's problem, with money on it.
- **"Use several sources."** Better, more complex, and you must decide what to do when they
  disagree — which is a policy question with no correct answer.
- **"Use a deeper pool."** Raises the cost of the attack in proportion to depth. It is a
  price, not a barrier, and flash loans mean the attacker need not own the capital.

There is no line of code that fixes this. That is the lesson.

### The honest parts of the design

**Slippage protection is the caller's job.** Every swap takes `minOut` and a `deadline`. A
front-runner can see your transaction, trade ahead of it, and leave you a worse price; a
`minOut` you chose is what stops that turning into an unbounded loss. Passing `0` is passing
your wallet to whoever is watching the mempool.

**The liquidation bonus is not generosity.** Without it, nobody would spend gas closing
somebody else's bad position, and bad debt would simply accumulate. Ten percent is a wage
for a job the protocol needs done, paid by the borrower who let it happen.

**Interest accrues lazily.** `_accrue` folds interest into the debt whenever a position is
touched. Simple, and it means `totalDebt` understates reality between touches. Real
protocols use a global index that ticks for everyone. Replacing this is one of the
exercises, and it is more subtle than it looks.

**`MINIMUM_LIQUIDITY` is burned on the first deposit.** A thousand wei of shares that nobody
owns, so the pool can never be fully drained and the share price cannot be manipulated by
donating to an empty pool. This is a fix for a real Uniswap V2 attack, carried over
deliberately.

**The dangerous function is named `unsafeSpotTvdPerGrain`.** Not `getPrice`. If a function
returns something that must not be trusted, the name is the cheapest warning you will ever
write — and `GrainLoans` calls it anyway, which is exactly what a real codebase does under
deadline.

## Walk through it

1. `harvest()` some GRAIN.
2. Seed the pool with `addLiquidity`. Note `k`.
3. Swap a small amount. Check `quote` first, then compare with what you received.
4. Now swap something large — a tenth of the pool. Look at the price you got versus the
   headline rate. That is slippage, and it is why `quote` exists.
5. Check `k` after each swap. It only grows.
6. Supply TVD to `GrainLoans` from another account. Deposit GRAIN, borrow, watch
   `healthFactor`.
7. Borrow to near the limit, then have someone else swing the price and liquidate you.

Then run the attack:

8. Record `unsafeSpotTvdPerGrain()`.
9. Swap a large amount of TVD for GRAIN. Record it again.
10. Deposit collateral and call `availableToBorrow`. Compare with step 8's valuation.
11. Borrow the maximum. Swap the GRAIN back. Record the price a third time.
12. Add up what you hold, and what you owe, and decide whether you would repay.

## What actually happened on chain

```
Swapped(who: 0x…, tvdIn: true, amountIn: 500e18, out: 285e18, reserveTvd: …, reserveGrain: …)
CollateralDeposited(who: 0x…, amount: 300e18)
Borrowed(who: 0x…, amount: 1081.46e18, debt: 1081.46e18, price: 3.605e18)
Swapped(who: 0x…, tvdIn: false, amountIn: 285e18, out: …, reserveTvd: …, reserveGrain: …)
```

`Borrowed` records the **price the decision was made at**. That is deliberate: it is the
field a post-mortem reads first, and a protocol that does not log the price it trusted
cannot explain what happened to it.

## When a plain database is better

A market maker with an order book gives better prices at size, and an exchange can halt
trading, reverse an error, and know its customers.

AMMs earn their place for **long-tail assets with no professional market maker**, for
**permissionless listing**, and because they are **composable** — another contract can trade
against them without asking. That last property is also what made this module's attack
possible, and both facts are true at once.

Lending against volatile collateral, with no identity and no recourse, is a genuinely hard
problem that traditional finance solves with underwriting and courts. Over-collateralisation
is the on-chain substitute, and it is expensive: you must already have the money to borrow
the money.

## What this does not fix

- **Price manipulation.** The point.
- **Impermanent loss.** Liquidity providers can end up worse off than holding. Nothing here
  warns them.
- **Front-running.** `minOut` bounds your loss; it does not stop the sandwich.
- **Bad debt.** If the price gaps through the threshold faster than liquidators react, the
  position is underwater and the lenders eat it.
- **Interest rate policy.** `rateBps` is set by an admin. Real protocols use a utilisation
  curve, and that is an exercise.
- **Flash loans.** Not on this chain today — and they only reduce the *capital* needed for
  the attack, not its logic.

## Common mistakes

- **Using a spot price for anything.** Say it out loud once per project.
- **Swapping with `minOut = 0`.** Free money for a bot.
- **Assuming a TWAP is safe.** It raises the cost. Know by how much.
- **Liquidation thresholds too close to the LTV.** Ordinary volatility liquidates honest
  borrowers.
- **No liquidation bonus.** Nobody liquidates; bad debt piles up.
- **Not burning minimum liquidity.** The empty-pool donation attack.
- **Reading reserves instead of `balanceOf`, or the reverse, inconsistently.** Pick one and
  be able to say why.

## Security checklist

- [ ] Where does every price in the system come from, and who can move it?
- [ ] How much would it cost to move the price by 2×? By 10×?
- [ ] Can a position be opened and closed profitably within one transaction?
- [ ] Does `k` ever decrease?
- [ ] Can `removeLiquidity` take more than a proportional share?
- [ ] What happens to a position the price gaps past with no liquidator watching?
- [ ] Is `minOut` enforced on every path, including the ones added later?
- [ ] Does interest accrue correctly for a position untouched for a year?

## Extend it

1. **Fix the oracle.** Add a TWAP to `TownSwap` and read it from `GrainLoans`. Then measure
   what it now costs to run the attack, and how stale the price is during a real move.
2. Add a **utilisation-based interest rate**, so borrowing costs more when the pool is
   nearly drained.
3. Replace lazy accrual with a **global index**, and prove your version matches the old one
   on a suite of scenarios before you trust it.
4. Add a **circuit breaker**: pause borrowing if the price moves more than X% in one block.
   Then work out who can abuse the pause.
5. Write the **incident report** for the attack as if it had happened to a live protocol,
   using `docs/INCIDENT.md`. This is the deliverable the labs ask for, and it is the skill
   that gets people hired.

## Further reading

- [Uniswap V2 whitepaper](https://uniswap.org/whitepaper.pdf) — short, and worth reading in
  full.
- [Uniswap V2 oracle design](https://docs.uniswap.org/contracts/v2/concepts/core-concepts/oracles)
  — the TWAP, and its stated limitations.
- [Aave](https://docs.aave.com/) and [Compound](https://docs.compound.finance/) on
  liquidation mechanics.
- Search for post-mortems of price-oracle manipulation incidents and read three of them.
  You will notice how many describe exactly the four steps above.

**Next:** [Back to the module index →](README.md)
