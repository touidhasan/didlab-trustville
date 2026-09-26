# Lab 6 · Money, prices, and failure

**Deliverable:** a pull request, plus an incident write-up of a real exploit ·
**Time:** two hours

The last lab, and the one closest to what the job is actually like: an interface that moves
money, a price that can be lied about, and a post-mortem written as though it mattered.

## Part 1 — Trading, honestly presented (the PR)

Rebuild the Exchange card so that a user cannot accidentally lose money to something the
interface knew about and did not say.

**Quote and price impact.** Show what the trade returns *and* how far that is from the
pool's headline rate, as a percentage. Above a threshold you choose, warn — and defend the
threshold in your PR.

**Slippage tolerance the user controls.** Currently `minOut` is hardcoded at 1% below the
quote. Make it a setting with a sane default, and explain both directions: too tight and
the trade fails, too loose and a sandwich takes the difference.

**Honest balances.** Show what they hold, what they are spending, and what they will hold
afterwards. The commonest complaint about swap UIs is that people cannot tell what they
just agreed to.

**The borrow side.** Show the health factor with the liquidation threshold visible, and
warn before a borrow that leaves the position close to it. Show what price move would
liquidate them — that number is what a borrower actually needs and almost no interface
shows.

### Acceptance criteria

- [ ] Quote, effective rate and price impact shown before signing, updating as the user
      types.
- [ ] A user-controlled slippage setting with a documented default.
- [ ] Balances before and after, for both assets.
- [ ] Health factor with threshold, and the price move that would trigger liquidation.
- [ ] A borrow that would leave a position immediately liquidatable is refused by the
      interface with a reason, not merely reverted by the contract.
- [ ] Every failure state handled: rejected, reverted, insufficient allowance, empty pool.
- [ ] Amounts are never rendered as raw wei anywhere.
- [ ] CI green.

## Part 2 — The exploit (the incident write-up)

`GrainLoans` prices collateral with the AMM spot price. That price is two reserve numbers,
and anyone with enough capital can move them inside a single transaction.

**Run the attack on your local chain.** Not on DIDLab.

```bash
cd contracts && FOUNDRY_PROFILE=test forge test \
  --match-test test_ATTACK_InflateTheCollateralPriceAndWalkAway -vvv
```

Read the trace until you can account for every number. Then do it by hand through the UI on
a local town: swap the price up, deposit collateral, borrow against the inflated valuation,
swap back, keep the loan.

Then write it up in `docs/incidents/` **as though it had happened to a protocol you work
on, last night, with real money**. Use [the template](../INCIDENT.md).

### What the write-up must contain

- **Impact in numbers.** How much the pool lost, and what the collateral was actually worth.
- **A timeline** a reader could replay.
- **The mechanism**, precisely enough to reproduce.
- **Why it happened** — and keep asking until you reach a design decision, not a person.
  "The developer used spot price" is not the end of the chain. Why was that the easy thing
  to do? What would have made the safe thing easier?
- **How it was found.** In this case: a test written on purpose. Ask honestly whether a
  monitor would have caught it, and what that monitor would watch.
- **Actions**, each labelled *prevent*, *detect* or *reduce impact*. A plan with only
  prevention is not a plan — something always gets through.
- **What went right.** Real post-mortems record this.

### The sentence that has to be right

Somewhere in the write-up, state the vulnerability in one sentence. Not "the contract used
spot price" — that is the mechanism. The vulnerability is a belief about a number, and if
your sentence does not name the belief, keep rewriting it.

Every call in that attack succeeded. No function reverted. No key leaked, no reentrancy, no
compiler bug. That is what makes it worth a lab.

## Common ways this goes wrong

- **A price impact figure that is just the fee.** 0.3% is the fee. Impact is the curve.
- **Slippage measured against the wrong reference.** Compare with the pool's rate at
  submission, not with the mid-price.
- **A health factor that updates only after a transaction.** It changes whenever anyone
  trades. Decide how fresh yours needs to be.
- **A post-mortem that blames.** "The developer should have known" produces no fix. What
  made the unsafe path the default?
- **Running the attack on DIDLab.** It is shared. Use your own chain.

## Out of scope

Do not fix the vulnerability in this PR. Fixing it is the next piece of work and it needs
its own design; the guide prices the three standard options, and each buys a different
failure. Your job here is to present money honestly and to report the failure properly —
which, in the industry, are two different people's jobs and both are yours.

## Hand in

1. The PR, CI green, reviewed and approved.
2. The incident write-up in `docs/incidents/`.
3. Your review of someone else's PR **and** of their write-up. For the write-up, ask the
   one question that matters: could you cause this failure again from what they wrote?
