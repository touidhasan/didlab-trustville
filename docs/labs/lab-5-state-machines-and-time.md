# Lab 5 · State machines and time

**Deliverable:** a pull request: the governance interface, done properly · **Time:** two hours

A governance proposal moves through eight states, three of them on timers, and two of the
transitions need somebody to push a button. The contract handles this correctly. The
interface currently does not, and the gap between them is where most dApp bugs live.

## The job

Rebuild the module 12 part of the Council card so a resident who has never used a DAO can
follow a proposal from creation to execution without asking anyone what is going on.

## The specification

**Show the state, and what it means.** `Pending`, `Active`, `Succeeded`, `Defeated`,
`Queued`, `Executed`, `Canceled`, `Expired`. Each with a sentence. "Succeeded" does not
tell a user the money has not moved yet.

**Show the clock.** Pending and Active end at a known time; a queued proposal becomes
executable at a known time. Count down, live, and say what happens when the countdown
reaches zero.

**Show the vote.** For and against, as a bar. Quorum as progress toward a threshold, not a
raw number — 4% of supply means nothing to a reader without the denominator.

**Show what the proposal does.** Right now a proposal is a description string. Decode the
call: this proposal sends *N TVD* to *0x…*. A governance interface that cannot tell a voter
what they are voting for is a governance interface in name only.

**Fix the description problem.** Only the *hash* of the description is on chain, and
queuing and executing need the exact original text. Today the UI asks the user to paste it
and keeps a copy in `localStorage` — so a proposal created in one browser cannot be queued
in another, which for a DAO is a real failure.

Recover the text from the `ProposalCreated` event log, with the local copy as a fallback
rather than the source of truth. Then nobody has to paste anything.

**Guide the next action.** At every state, exactly one thing is worth doing: wait, vote,
queue, execute. Show that one thing. Anything else should be absent, not disabled without
explanation.

## Acceptance criteria

- [ ] All eight states render, each with a sentence a non-expert understands.
- [ ] Countdowns update live and are correct against **block time**, not the browser clock.
- [ ] Quorum shown as progress toward the requirement, with the requirement visible.
- [ ] Each proposal shows the decoded action: recipient and amount.
- [ ] Queue and execute work **in a fresh browser with empty local storage**. A reviewer
      will test exactly this.
- [ ] A user who has not delegated sees a clear warning that their tokens do not vote.
- [ ] A user who was not delegated at the snapshot sees why they cannot vote — and it says
      snapshot, not "no tokens", because those are different problems.
- [ ] All failure states handled as in lab 3.
- [ ] CI green.

## Technical requirements

**Block time, not wall time.** The chain's clock is what the contract uses. On a local
chain where you have time-travelled, the two are hours apart. Read the latest block's
timestamp and derive your countdowns from it, or your interface will confidently show the
wrong number.

**The event log is the source of truth** for the description. `localStorage` is a cache and
should be labelled as one in the code.

**Decode the calldata** with viem's `decodeFunctionData` against the TownToken ABI. Handle
a proposal whose calldata you cannot decode — show it as raw rather than crashing, because
one day somebody will propose something your UI has never seen.

## The question to answer in your PR

The Council's timings are one minute, ten minutes, two minutes — so a class can watch a
whole cycle. Real DAOs use days and weeks.

**What in your interface would break if the voting period were seven days?** Countdowns
rendered in seconds, a page that must stay open, a poll that runs every second for a week.
Name the specific things, and say which you would change.

## Common ways this goes wrong

- **`Date.now()` for countdowns.** Correct in the demo, wrong on any chain whose clock has
  drifted or been warped.
- **Storing the description only locally.** The bug you were asked to fix. A reviewer will
  open a private window.
- **Hiding the snapshot rule.** A user who wrapped after the proposal opened will be
  confused and then angry. Explain it before they try.
- **A timer per proposal, never cleaned up.** Ten proposals, ten intervals, none cleared on
  unmount.
- **Rounding quorum to zero.** Small numbers with 18 decimals round badly. Check the edges.

## Out of scope

No contract changes — the Governor and Timelock stay exactly as deployed. The multisig half
of the card is not part of this lab.

## Hand in

1. The PR, CI green, reviewed and approved.
2. Your review of someone else's PR. Open their branch in a **private window**, with no
   local storage, and try to queue a proposal somebody else created. That one test finds
   the bug this lab exists to fix.
3. An incident write-up if anything broke.
