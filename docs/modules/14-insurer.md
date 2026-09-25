# Module 14 · Parametric insurance and the oracle problem

## The problem

A farmer's field dries out. They file a claim. An assessor visits, forms a view about how
much was lost and how much of it was really the drought, and some weeks later a figure
arrives. The wait is the product failing at exactly the moment it was bought for.

Underneath sits a harder problem than insurance. **A contract cannot look out of the
window.** Everything modules 1–13 know is true by construction: a token balance is whatever
the contract says it is, a deed belongs to whoever the contract says owns it. Rainfall is
different. It is a fact about the world, and the only way it gets on chain is that somebody
outside types it in.

This is the module where the chain stops being self-contained, and it is worth being blunt
with students about what that costs. Every guarantee in the previous thirteen modules was
mathematical. This one rests on people.

## Why a blockchain — and exactly where it stops

**Parametric** insurance pays on a measurement rather than on an assessed loss. If the
rainfall for the insured period comes in under the trigger, the policy pays its full
coverage. One transaction, which anybody may send, and no discretion anywhere in the path.

That is a genuine improvement: no assessor, no negotiation, no "we're reviewing your
claim", and no insurer deciding it would rather not pay this quarter. The trade is
**basis risk** — a farmer whose crop survived a dry spell still gets paid, and a farmer
ruined by hail gets nothing. You give up accuracy to buy speed and certainty. That suits
some risks (drought, flight delay, earthquake magnitude) and badly suits others.

Where it stops is the measurement. The contract's guarantee is "we will pay whatever the
oracle says"; it cannot be "we will pay when it is really dry". Everything below is about
narrowing that gap, and none of it closes it.

## Design

```
RainOracle      reporters submit independently for a finished period
                anyone may finalize once the quorum is in; the answer is the MEDIAN
                every submission stays readable, in submission order, for ever

CropInsurance   buy(period, coverage)   only for a period that has not started
                settle(id)              anyone; pays if mm < the policy's own trigger
                reserved                every live policy's cover, locked against the pool
```

### Why the median, not the mean

A mean lets one reporter drag the answer anywhere. Report a million millimetres and the
average is destroyed. With a median, a single dishonest reporter moves the result by one
position in the sorted list — a test in this module submits 9000mm against honest readings
of 10 and 12, and the answer comes out 12.

To control a median outright you must control **more than half** the reporters. That is the
entire argument for M-of-N, and it is worth saying precisely what it buys: not honesty, but
a price. Capturing the oracle now costs an attacker the effort of running more reporters
than the honest operators do. A second test in this module has three of five reporters
submit zero and the oracle duly reports a drought. Nothing in the contract prevents it.
**M-of-N converts a trust problem into a cost problem; it does not remove it.**

### Three things the design deliberately does not fix

- **Correlated sources.** Three reporters reading the same broken weather station agree
  perfectly and are perfectly wrong. Independence of *reporters* is not independence of
  *sources* — and if all three call the same weather API, you have one source wearing three
  hats.
- **Copying.** A reporter who can see the others' submissions can copy instead of measure.
  The fix is the commit–reveal from module 6, and it is an exercise below.
- **Silence.** If reporters stop, there is no reading, and a policy that obviously should
  pay cannot settle. The contract has no way to compel anyone to speak.

Liveness and honesty pull against each other: a low quorum keeps answers flowing and is
easier to capture; a high one resists capture and is easier to stall. There is no setting
that wins both, which is why it is a parameter and not a constant.

### Three rules that keep the insurer honest

**Insure the future only.** A policy may only cover a period that has not begun. Otherwise
anyone could watch the drought happen and then buy cover for it. For the same reason,
reporters may only report a period that has already ended — a reporter holding a policy
must not be able to write their own payout.

**Reserve before you sell.** Every policy's full coverage is locked against the pool the
moment it is sold, and the contract refuses a sale it cannot back. An insurer that sells
more cover than it holds is solvent only while claims stay rare, which is precisely not
when they arrive. `withdrawSurplus` can take the profit and never the reserve.

**The trigger is frozen at purchase.** `setTerms` changes what the insurer sells next; live
policies keep the trigger they were sold with. An insurer that can move the goalposts after
taking the premium is not selling insurance.

**No reading is not a reading of zero.** `reading()` returns a `finalized` flag beside the
figure. An unreported period reads `0mm` — and if the insurer trusted the number without
the flag, every quiet period would look like a total drought and drain the pool. It is the
cheapest possible bug and one of the most expensive.

## Try it

You need the reporter nodes running: see
[`services/rain-reporter/README.md`](../../services/rain-reporter/README.md). Three keys,
three stations, each with `REPORTER_ROLE`.

1. **Watch a period settle.** Leave three reporters running. Each reports the last finished
   period; the figures differ by a millimetre or two; one of them finalises. The town page
   shows who said what.
2. **Buy cover** for the next period. Note that the premium leaves immediately and the
   pool's "still sellable" figure drops by the *full* cover, not the premium.
3. **Try to insure the period that is running.** Refused.
4. **Try to buy more cover than the pool holds.** Refused, with the available figure in the
   error.
5. **Settle** once the reading is in. Either the cover arrives in one transaction, or the
   policy expires and the cover returns to the pool — and the premium stays, which is the
   insurer's entire business model.
6. **Settle someone else's policy.** It pays them, not you.
7. **Run one reporter with `--lie 9000`.** The median shrugs. Then look at the period's
   reports on the explorer: the lie is on the record, next to the address that told it.
8. **Run two of three with `--lie 0`.** The oracle reports a drought and every policy pays.
   Discuss what just happened, and what it would have cost an attacker in a town with
   twenty reporters instead of three.
9. **Stop all the reporters.** Nothing settles. Nobody can be made to speak.

## Extend it

1. **Commit–reveal for reporters**, reusing module 6. Reporters commit a hash, then reveal.
   Copying becomes impossible; the cost is a second transaction and a reveal deadline — and
   a new failure mode when someone commits and never reveals. Design the penalty.
2. **Stake and slash.** Require reporters to post a bond, and let anyone challenge a report
   that sits far from the median. Now decide the hard part: who judges a challenge, and what
   stops that judge being the new single point of trust?
3. **Pay for liveness.** Give the finaliser a small fee from the pool, so somebody always
   has a reason to push the button. Then work out whether that fee can be gamed.
4. **Replace the gauge with a real API.** One function in the reporter decides what a node
   believes. Swap it, then argue about whether you have three sources or one.
5. **Tranche the pool.** Let funders take different slices of the risk, and watch the module
   turn into module 15's problem.

## Security checklist

- [ ] Can a reporter report a period they hold a policy on, after seeing the weather?
- [ ] Can the same reporter be counted twice? Can a reporter be added mid-period to swing it?
- [ ] Does the insurer ever act on a figure whose `finalized` flag is false?
- [ ] Can the admin change a trigger or premium in a way that affects a policy already sold?
- [ ] Can the pool be drained below the cover it has promised — by a sale, or by a withdrawal?
- [ ] Can a policy be settled twice, or settled by someone who profits from the timing?
- [ ] If every reporter goes silent, whose money is stuck, and for how long?
- [ ] How many reporter keys would an attacker need, and what would that cost compared with
      the pool they could drain?
