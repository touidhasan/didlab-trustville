# Module 12 · DAO governance

| | |
| --- | --- |
| **Contracts** | `VoteToken.sol`, `TownGovernor.sol`, `TownTimelock.sol` |
| **Stop** | Council |
| **Standards** | ERC-20Votes, ERC-6372, OpenZeppelin Governor + TimelockController |
| **Stamp** | none — governance stamps nobody |

## The problem

Module 11 gave the town a treasury controlled by a handful of named owners. Better than one
key, and still a small group deciding for everyone.

The obvious next step is to let the town vote. Which raises a harder question: **how do you
make a vote binding?** A poll is easy. A poll whose result *automatically* moves the money,
with nobody able to ignore it, is a different thing — and it is the only version that counts
as governance rather than consultation.

## The idea

Three contracts with three jobs, and the separation is the design:

- **vTVD** (`VoteToken`) — wraps TVD and records *checkpointed* balances, so voting power
  can be measured as it stood at a past moment.
- **The Governor** — runs proposals, voting windows, quorum and counting. It holds no money
  at all.
- **The Timelock** — **holds the money**, accepts instructions only from the Governor, and
  waits before acting on them.

The Council cannot spend. It can only tell the Timelock to spend, and only after a proposal
has actually passed. That indirection is the whole point: a vote is not advice, it is the
only route to the treasury.

## Key terms

**Checkpoint.** A record of a balance at a block or timestamp. Ordinary ERC-20 knows only
"now"; voting needs "then".

**Snapshot.** The moment at which voting power is measured for one proposal — the end of the
voting delay. Buying tokens after the snapshot gives you no votes.

**Delegation.** Assigning your voting power to an address. **Tokens that are not delegated
count for nobody, including you.** This is the single most common cause of "why did my vote
not register".

**Quorum.** The minimum participation for a vote to count. Trustville uses 4% of wrapped
supply, matching common practice — and worth noticing, because 4% is not a democratic
threshold by any normal standard.

**Timelock delay.** The waiting period between a proposal passing and executing. It exists
so that people who disagree can react — sell, exit, raise the alarm — before it lands.

## How it works

```
wrap + delegate ─▸ propose ─▸ [voting delay] ─▸ [voting period] ─▸ queue ─▸ [timelock delay] ─▸ execute
                                   ▲                                              ▲
                              snapshot taken                             anyone may push the button
```

| Step | Call | Notes |
| --- | --- | --- |
| Get voting power | `depositAndSelfDelegate(amount)` | Wrap **and** delegate in one transaction |
| Propose | `propose(targets, values, calldatas, description)` | Threshold is 0 here — anyone may |
| Wait | — | Voting delay, 60 seconds on Trustville |
| Vote | `castVote(proposalId, support)` | 0 against, 1 for, 2 abstain |
| Queue | `queue(targets, values, calldatas, descriptionHash)` | Sends it to the Timelock |
| Wait | — | Timelock minimum delay |
| Execute | `execute(targets, values, calldatas, descriptionHash)` | Anyone |

Wiring, set at deployment and worth memorising:

- **PROPOSER** on the Timelock — the Governor, and nothing else.
- **EXECUTOR** — `address(0)`, meaning anyone may execute a matured proposal.
- **ADMIN** — nobody, after the deployer renounces.

That last line is the one that makes it real. While a deployer still holds the Timelock's
admin role, the DAO is theatre: the admin can schedule whatever they like. Renouncing is the
moment governance begins, and it is irreversible.

## The detail that matters

**Wrapping is not voting power.**

```solidity
function depositAndSelfDelegate(uint256 amount) external {
    depositFor(msg.sender, amount);
    _delegate(msg.sender, msg.sender);
}
```

This convenience function exists because the two-step version catches out real DAOs
constantly. Holders wrap, assume they can vote, and discover at the count that their power
was zero. The protocol is behaving correctly; the mental model is wrong. Delegation is
explicit by design — it is what lets you lend your voice to someone who follows the
proposals more closely than you do.

**The clock is timestamps, not blocks (ERC-6372):**

```solidity
function clock() public view override returns (uint48) { return uint48(block.timestamp); }
function CLOCK_MODE() public pure override returns (string memory) { return "mode=timestamp"; }
```

With the default block-number clock, "a ten-minute vote" must be written as a number of
blocks, and silently changes length whenever block time changes. On a QBFT chain whose block
time you control, that is a foot-gun waiting for the day someone retunes the validators.
Timestamps make governance periods mean what they say.

**The snapshot defeats vote-buying by timing.** Voting power is read at the snapshot, so
reading a proposal and *then* acquiring tokens achieves nothing. It does not defeat
vote-buying in general — someone who accumulates before proposing has all the power they
paid for, which is not a bug but the design.

**One token, one vote.** Say it plainly: this is governance proportional to wealth. The
richest holder decides. Delegation, quorum and timelocks soften the edges; none of them
change the rule. If that bothers you, good — it should, and "how to govern on chain without
plutocracy" is an open problem with a serious literature. Quadratic voting, one-person-one-
vote with proof of personhood, conviction voting and reputation systems are all attempts,
and none is settled.

**Proposals are identified by their description.** The proposal id is a hash of targets,
values, calldatas and `keccak256(description)`. Change one character of the description at
queue or execute time and the id is different, so the call reverts with a state error about
a proposal that does not exist. The Trustville UI stores the exact description alongside the
id for this reason — after we hit it, hard, in production.

## Walk through it

1. **Get power.** Approve TVD to the VoteToken, then `depositAndSelfDelegate`.
2. Check `getVotes(you)`. If it is zero, you skipped the delegation.
3. **Propose** a payment from the Timelock — target the TVD token, calldata a `transfer`.
   Keep the description text; you will need it exactly.
4. Check `state(proposalId)`: `Pending`. Wait out the voting delay.
5. `Active`. Cast votes from several accounts.
6. After the voting period: `Succeeded` — or `Defeated`, or, if too few voted,
   `Defeated` on quorum, which is a good failure to cause on purpose at least once.
7. **Queue.** Now the Timelock is holding it, and `state` is `Queued`.
8. Try to execute immediately. It reverts — the delay has not passed.
9. Wait, then **execute from a completely different account**. The vote is the authority.

Then try to break it:

10. Wrap tokens *after* the snapshot and vote. Your power is zero.
11. Propose the same thing twice. The second reverts — same id, already exists.
12. Try to make the Timelock pay you directly, without a proposal. There is no path.

## What actually happened on chain

```
ProposalCreated(proposalId: 8471…, proposer: 0x…, targets: […], voteStart: …, voteEnd: …, description: "…")
VoteCast(voter: 0x…, proposalId: 8471…, support: 1, weight: 500e18, reason: "")
ProposalQueued(proposalId: 8471…, etaSeconds: …)
CallScheduled(id: 0x…, index: 0, target: 0x…, value: 0, data: 0x…, predecessor: 0x0, delay: …)
CallExecuted(id: 0x…, index: 0, target: 0x…, value: 0, data: 0x…)
ProposalExecuted(proposalId: 8471…)
```

Two ids run in parallel: the Governor's `proposalId` and the Timelock's operation `id`. They
are different hashes of overlapping data, and confusing them is a rite of passage. The
Governor's id identifies the *vote*; the Timelock's identifies the *scheduled call*.

## When a plain database is better

Almost every organisation, almost always. A committee with a constitution, minutes and a
bank mandate is faster, cheaper, capable of nuance, and can be sued when it goes wrong.

On-chain governance earns its place when the members **cannot rely on a shared legal
system** — pseudonymous, international, no incorporation — or when the thing being governed
is itself on chain and the alternative is trusting a small team's keys. Note how much real
DAO activity still runs on off-chain signalling (Snapshot) with a multisig executing, which
is a candid admission that full on-chain governance is expensive and slow.

## What this does not fix

- **Plutocracy.** As above.
- **Voter apathy.** Quorum of 4% exists because 50% is unachievable. Most holders never
  vote, and a determined 5% can therefore run things.
- **Proposal quality.** Nobody checks that calldata does what the description claims. Read
  the calldata; this is exactly the module 11 memo problem with higher stakes.
- **Flash-loan governance attacks.** Snapshots help; a token that can be borrowed before the
  snapshot is still dangerous. Real incidents exist.
- **Speed.** Every delay that protects you also prevents you responding to an emergency.
  Serious protocols keep an emergency multisig, and then must explain why they have a DAO.
- **Legal standing.** A DAO is not a legal person in most jurisdictions, and members may be
  a general partnership without knowing it.

## Common mistakes

- **Wrapping without delegating.** Zero votes, no error.
- **Leaving the Timelock admin assigned.** The DAO is decorative until it is renounced.
- **Giving the Governor `EXECUTOR`** and thinking that is tighter. Open execution is
  deliberate; it stops a queued proposal being held hostage.
- **Changing the description string** between propose, queue and execute.
- **Quorum too high.** Nothing ever passes and the treasury is frozen.
- **Quorum too low.** One holder is the government.
- **Voting with the block-number clock on a chain with variable block time**, then wondering
  why the vote ended early.

## Security checklist

- [ ] Who holds `PROPOSER` on the Timelock? Anyone besides the Governor?
- [ ] Has the deployer renounced `TIMELOCK_ADMIN_ROLE`? Verify it on chain, do not assume.
- [ ] Does the Governor hold funds? It should hold none.
- [ ] Can a proposal change the Timelock's roles — and should it be able to?
- [ ] What fraction of supply is delegated, and how much does the largest holder control?
- [ ] Can a proposal be executed without being queued?
- [ ] Is the timelock delay long enough for anyone to actually react?

## Extend it

1. Add `GovernorPreventLateQuorum`, so a proposal that reaches quorum at the last second
   extends the vote. Work out the attack it prevents.
2. Give the Timelock a `CANCELLER`, then decide who should hold it. You have reinvented the
   guardian debate that every major protocol has had.
3. Replace one-token-one-vote with quadratic voting, and then break it with sybil accounts —
   which will teach you why nobody has deployed it to a treasury of consequence.
4. Make the module 11 treasury a Timelock proposer for emergencies only, and write the
   governance policy that says when that is legitimate.

## Further reading

- [OpenZeppelin Governance](https://docs.openzeppelin.com/contracts/5.x/governance)
- [ERC-6372: contract clock](https://eips.ethereum.org/EIPS/eip-6372)
- [ERC-5805: voting with delegation](https://eips.ethereum.org/EIPS/eip-5805)
- Compound's Governor Bravo, the design everything here descends from.
- Read a post-mortem of a real governance attack — Beanstalk (2022) is the canonical one —
  and map each step onto the protections above.

**Next:** [Module 13 · Charity →](13-charity.md)
