# Modules 11–12 · Multisig treasury, Town governance

## The problem

Public money spent on one person's say-so, and decisions taken where nobody can check them.
Both are governance problems, and they have two different answers — which is exactly why
this stop contains both.

## Two answers, honestly compared

| | Multisig (module 11) | DAO (module 12) |
| --- | --- | --- |
| Who decides | A few named signers | Whoever holds the voting token |
| Speed | Minutes | Delay + voting period + timelock |
| Visibility | The payment is public, the argument is not | Proposal, votes and reasoning all public |
| Failure mode | Signers collude, or lose their keys | Whales decide; voters do not turn up |
| Good for | An operating budget, a small team | Big irreversible decisions, open membership |

Neither is "more decentralised" in a useful sense. The real question is **who should be
able to stop a payment**, and how fast the group needs to move. Ask students which one they
would want for their department's coffee fund, and which for its building.

## Design

```
TownTreasury   M-of-N multisig. Owners confirm; anyone may execute once M have signed.
               Owner changes go through the multisig itself — no back door.
VoteToken      wraps TVD 1:1 into vTVD, counted by TIMESTAMP (ERC-6372)
TownGovernor   proposals, voting, quorum (4%), queue and execute through the Timelock
TownTimelock   holds the governed funds; only the Governor may schedule; nobody is admin
```

**The Council does not hold the money.** The Timelock does, and it only accepts
instructions from a proposal that passed. That indirection is the whole design: a vote is
not advisory, it is the *only* path to the treasury. A test proves even the town admin
cannot schedule a payment directly.

**Why four phases**, each earning its place:

| Phase | Default | Why it exists |
| --- | --- | --- |
| Voting delay | 1 min | A snapshot everyone can see before voting opens, so nobody reads a proposal and then buys tokens to beat it |
| Voting period | 10 min | The window to cast a vote |
| Timelock delay | 2 min | Time to react to a passing proposal you hate — you can exit before it executes |
| Execution | — | Anyone may push the button; the vote is the authority, not the sender |

Real DAOs use days and weeks for the same phases. These are lab-sized so a class can watch
a whole cycle; the ratios, and the reasons, are unchanged.

**Timestamps, not block numbers.** The voting token implements ERC-6372 in timestamp mode.
With the default block-number clock, "a 10 minute vote" must be written in blocks and
silently changes length whenever block time does. This bites people on real deployments.

## The two things that catch everyone out

1. **Wrapping is not voting power.** vTVD you hold but never delegated counts for nobody —
   including you. A test has a holder of 900 tokens lose to a holder of 100 who delegated.
   The UI warns when you are in that state, because real DAOs lose votes to it constantly.
2. **Power is measured at the snapshot.** Wrapping and delegating *after* a proposal opens
   gives you nothing on that proposal. Another test buys 900 tokens mid-vote and still
   counts zero.

## Try it

1. **Wrap some TVD** and watch your voting power appear. Then unwrap, wrap again *without*
   delegating (call `depositFor` directly on the explorer), and see power stay at zero.
2. **Propose a payment** from the Council's funds to a classmate, with a reason.
3. Watch it sit in **Pending** until the voting delay passes, then **Active**.
4. **Vote**, from two or three accounts, some for and some against.
5. After the period closes, the state becomes **Succeeded** or **Defeated**. Queue a
   successful one — and note it needs the *exact* description text; a single changed
   character produces a different proposal id and the call fails.
6. Wait out the timelock, then **execute**. Check the Timelock's balance on the explorer
   before and after.
7. Now do the same spend through the **multisig**: propose, get a second signature, execute.
   Time both. Which felt safer? Which would you want for a €2m decision?

## Extend it

1. Add a quorum that scales with turnout, or a minimum proposal threshold, and argue for the number.
2. Give the multisig a spending limit above which it must instead go to the DAO.
3. Let the DAO add and remove multisig signers, so the slow body governs the fast one.

## Security checklist

- [ ] Can anyone reach the Timelock's funds without a passed proposal?
- [ ] After deployment, does anyone still hold admin rights over the Timelock?
- [ ] Can an owner's confirmation be counted twice? Can a payment execute twice?
- [ ] If the multisig's inner call fails, is the payment left executable or silently consumed?
- [ ] Can the owner set be changed without the multisig's agreement?
- [ ] What stops one holder with a majority of vTVD from simply voting themselves the treasury?
