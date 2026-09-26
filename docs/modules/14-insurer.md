# Module 14 · Insurer and oracle

| | |
| --- | --- |
| **Contracts** | `RainOracle.sol`, `CropInsurance.sol` |
| **Stop** | Insurer |
| **Pattern** | M-of-N oracle with on-chain median; parametric insurance |
| **Stamp** | Module 14 (awarded to the **policyholder** on purchase) |

## The problem

A smart contract can see its own storage, its own balance, the block timestamp, and nothing
else. It cannot see the weather, a share price, an election result, or whether a parcel
arrived.

This is **the oracle problem**, and it is the boundary of what blockchains can do. Every
other module in Trustville has brushed against it — module 4's origin string, module 7's
issuer, module 13's arbiter — and this one confronts it directly.

Crop insurance makes it concrete. A farmer wants cover against drought. The payout depends
on rainfall. Rainfall is a fact about the sky.

## The idea

Two contracts, and the split matters.

**`RainOracle`** answers one question: how much rain fell in period *N*? Several independent
reporters submit a number, and once a quorum has reported, anyone may finalise: the contract
takes the **median** and writes it down for ever.

**`CropInsurance`** sells **parametric** cover. Not "we will assess your loss" but "if the
oracle's reading for period N is below the trigger, you receive your coverage amount". No
adjuster, no claim form, no argument — and no attempt to measure your actual loss.

## Key terms

**Oracle.** A mechanism for getting off-chain facts on chain. Every oracle is a trust
assumption with good manners.

**M-of-N reporting.** N reporters, any M constitute a quorum. Here `MIN_QUORUM` is 2 and
`MAX_REPORTS` is 9.

**Median, not mean.** The middle value. One reporter who submits a wild number moves the
mean a lot and the median not at all. This one choice is most of the oracle's robustness.

**Parametric insurance.** Payout triggered by a measured index rather than an assessed loss.
Real, widely used in agriculture and catastrophe cover, and it trades accuracy for speed and
cheapness.

**Basis risk.** The gap between the index and your actual loss. Your field floods while the
gauge stays dry; you get nothing, and the policy worked exactly as written.

**Reserving.** Setting aside the money to pay a promise at the moment the promise is made.

## How it works

```
period ends ─▸ reporters report ─▸ quorum reached ─▸ anyone finalises (median) ─▸ policies settle
```

**Oracle**

| Function | Who | What |
| --- | --- | --- |
| `report(period, mm)` | `REPORTER_ROLE` | Only for a **finished** period, once each |
| `finalize(period)` | **anyone** | At or above quorum; computes the median |
| `reading(period)` | anyone | `(finalized, mm, count)` |
| `reportsOf(period)` | anyone | Every individual submission, and who made it |
| `setQuorum(n)` | admin | Between 2 and 9 |

**Insurance**

| Function | Who | What |
| --- | --- | --- |
| `fund(amount)` | anyone | Adds to the pool |
| `buy(period, coverage)` | anyone | Only a period that has **not begun** |
| `settle(id)` | **anyone** | Reads the oracle, pays or expires |
| `available()` | view | Held minus reserved |
| `setTerms(trigger, premiumBps)` | admin | New policies only |

## The detail that matters

**Nobody reports the future:**

```solidity
if (period >= currentPeriod()) revert PeriodNotOver();
```

A reporter who could report a period still running — or one yet to start — could buy a
policy and then write their own payout. The rule removes the possibility rather than
trusting the reporter.

**Nobody insures the past:**

```solidity
if (period <= oracle.currentPeriod()) revert PeriodAlreadyStarted();
```

The mirror image. Buying cover for a drought you already know happened is not insurance, it
is a withdrawal. Together, these two lines mean a policy is always bought before the fact
and reported after it, with no window where anyone knows both.

**The median is computed on a copy:**

```solidity
uint32[] memory a = new uint32[](n);
for (uint256 i; i < n; i++) a[i] = values[i];
// insertion sort on `a`
```

Sorting the stored array in place would be cheaper — and would destroy the audit trail.
`reportsOf` must keep returning who said what, in submission order, for ever. A reporter
whose number sat far from the median is permanently visible, which is the accountability
mechanism this design has instead of a penalty. Insertion sort is the right algorithm at
n ≤ 9; the bound is what makes an on-chain sort defensible at all.

**One liar cannot move the answer.** With reports of 10, 12 and 900, the median is 12. There
is a test called `test_OneLiarCannotMoveTheAnswer` that says exactly this.

**A majority of reporters can move it to anything.** With 10, 900 and 900, the median is
900. There is also a test called `test_AMajorityOfReportersControlsTheAnswer`, and it is the
more important of the two. **The oracle does not create truth; it makes corrupting the truth
require a majority of a known set of parties.** That is the entire security claim, stated
honestly. Whether it is enough depends on who those parties are — which is a governance
question, not a cryptographic one.

**An unreported period is not a drought:**

```solidity
(bool finalized, uint32 mm,) = oracle.reading(p.period);
if (!finalized) revert NoReadingYet();
```

Solidity's default for an unset `uint32` is zero, and zero millimetres of rain is the most
extreme drought possible. A settlement that read the raw value would pay out every policy
for every period nobody bothered to report. The `finalized` flag exists so that "no answer"
can never be mistaken for "the worst possible answer" — and **this class of bug has drained
real protocols.** Whenever a contract reads a number from somewhere else, ask what the
uninitialised value means.

**Coverage is reserved at sale, not at settlement:**

```solidity
uint256 free = available();              // held − reserved
if (coverage > free) revert NotEnoughInThePool(free, coverage);
reserved += coverage;
```

The insurer can never promise more than it holds. A real insurer does the opposite — it
writes far more cover than its capital, on the actuarial bet that not everything pays at
once, which is why insurers can fail. This contract cannot become insolvent, and the price
of that is capital efficiency: to cover a thousand farmers you must hold every penny of a
thousand payouts.

Fully-reserved versus fractionally-reserved is a real design axis, not a beginner's
simplification. Know which one you are building.

**The trigger is frozen at purchase:**

```solidity
triggerMm: triggerMm,   // copied into the policy, not read at settlement
```

`setTerms` changes what *new* policies are sold at. A live policy keeps what it was sold
with. An insurer who could raise the trigger after taking your premium is not selling
insurance, and a contract that read the current value at settlement would be exactly that
insurer.

**Settlement is a measurement, not a decision.** Anyone may call `settle`, because the
caller cannot influence the outcome — the reading is already fixed. A holder who has lost
their phone still gets paid, by a stranger, for the cost of gas. Compare with modules 5, 10
and 13, where a human must judge: here the judgement was moved into the oracle, and the
payment is arithmetic.

## Walk through it

1. Read `currentPeriod()`. Buy cover for the **next** period.
2. Try to buy for the current one. `PeriodAlreadyStarted`.
3. Wait for the period to end.
4. Watch the three reporter services submit. `Reported` events, one per reporter.
5. Call `reportsOf(period)` and read the three numbers.
6. `finalize(period)`. The median is written.
7. `settle(id)` — from an account that is not the holder. Paid or expired, depending.

Then break it:

8. Run a reporter with `--lie` and see the median ignore it. Then check `reportsOf`: the lie
   is there for ever, next to its author's address.
9. Run **two** reporters with `--lie` out of three. Now the median is theirs.
10. Try to settle a period nobody reported. `NoReadingYet` — not a payout.

## What actually happened on chain

```
Reported(period: 480123, reporter: 0x…, mm: 11, count: 1)
Reported(period: 480123, reporter: 0x…, mm: 13, count: 2)
Reported(period: 480123, reporter: 0x…, mm: 900, count: 3)
Finalized(period: 480123, mm: 13, count: 3, by: 0x…)
PolicySettled(id: 5, holder: 0x…, paid: false, mm: 13, amount: 0)
```

Median of 11, 13 and 900 is 13. The 900 is preserved, attributable and permanent.

## When a plain database is better

For crop insurance in a country with a functioning insurance market, the incumbent wins: it
assesses actual loss, it is regulated, it is capitalised, and it can be sued.

Parametric cover on chain earns its place where **conventional insurance does not reach** —
smallholders whose claims cost more to assess than to pay, regions with no adjusters — and
where the *speed* matters: a payout hours after the reading, not months after a visit. Real
programmes of exactly this kind exist and pay out to farmers today, mostly without a
blockchain, which should tell you the parametric idea is doing more work than the ledger is.

## What this does not fix

- **The oracle problem.** It is reduced to "trust a majority of these N", not eliminated.
- **Basis risk.** The index is not your loss. The most common complaint about real
  parametric products, and unfixable in principle.
- **Reporter collusion.** A majority decides the weather.
- **Reporter apathy.** No quorum, no reading, no settlement — policies simply hang.
- **Where the number came from.** A reporter's gauge could be broken, or simulated. In this
  repository it *is* simulated, and being clear about that is part of the lesson.
- **Insurer insolvency by another route.** Full reserving fixes the promise, not the admin's
  `withdrawSurplus`.

## Common mistakes

- **Treating an unset reading as data.** The zero-drought bug above.
- **Using the mean.** One outlier, one wrong answer.
- **Sorting the stored array.** Cheaper, and it deletes the evidence.
- **Reading the current trigger at settlement.** Lets the insurer rewrite live policies.
- **Letting reporters report the current period.** Self-dealing.
- **Unbounded report arrays.** An on-chain sort with no cap is a gas bomb.
- **Not reserving.** The pool sells more cover than it holds and the last claimant finds it
  empty.
- **A single reporter.** Then you have an oracle with a single point of failure and a lot of
  extra code.

## Security checklist

- [ ] Can a reporter report the current or a future period? Report twice?
- [ ] Can a period be finalised below quorum? Finalised twice?
- [ ] What does a settlement do when the oracle has no reading?
- [ ] Can `reserved` ever exceed the token balance?
- [ ] Can a policy be settled twice, or by someone other than the holder — and should
      either matter?
- [ ] Does `setTerms` affect live policies?
- [ ] Can the admin withdraw below `reserved`?
- [ ] Who holds `REPORTER_ROLE`, how many are there, and who could grant themselves more?

## Extend it

1. Require reporters to stake, and slash anyone whose report sits far from the median. Then
   work out how a majority uses slashing to punish the one honest reporter.
2. Add a dispute window between finalisation and settlement, and decide who resolves it.
3. Weight the median by stake, and argue about whether that is an improvement or module 12's
   plutocracy in a lab coat.
4. Replace the simulated gauge with a real weather API in `services/rain-reporter`, and
   notice you have simply moved the trust to whoever runs that API.
5. Add fractional reserving with a solvency ratio, then simulate a year where every policy
   pays.

## Further reading

- [Chainlink's oracle problem overview](https://chain.link/education-hub/oracle-problem)
- The reporter service in this repository:
  [`services/rain-reporter`](https://github.com/touidhasan/didlab-trustville/tree/main/services/rain-reporter)
- Read about index-based crop insurance programmes in practice, and look specifically for
  what farmers say about basis risk.

**Next:** [Module 15 · Swap and lending →](15-defi.md)
