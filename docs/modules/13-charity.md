# Module 13 · Charity

| | |
| --- | --- |
| **Contract** | `TownCharity.sol` |
| **Stop** | Charity |
| **Pattern** | Milestone crowdfunding with pull refunds |
| **Stamp** | Module 13 (awarded to the **donor** on pledging) |

## The problem

You give money to a cause. Then what?

Two failures dominate charitable giving, and they are different. **The campaign does not
reach its target**, so the money is spent on a half-built well that helps nobody — the case
Kickstarter's all-or-nothing rule exists to prevent. And **the money arrives but the work
does not**, which no funding platform solves, because once the funds are released the
donor's leverage is gone.

Traditional charity answers the second with audits, regulators and annual reports: slow,
after the fact, and only as good as the auditor.

## The idea

Two mechanisms stacked.

**All or nothing.** Pledges sit in the contract. Reach the goal by the deadline or every
donor takes their money back in full.

**Milestones.** The goal is split into two to five stages, declared up front, each with a
description and an amount. Money is released one stage at a time, and only after the
beneficiary posts evidence and an arbiter approves it. Reject a milestone and the campaign
is cancelled — donors get back their share of everything not yet released.

The donor's leverage survives past the funding date. That is the part traditional
crowdfunding does not have.

## Key terms

**Milestone.** A stage of work with a fixed amount attached. `Waiting → Submitted →
Approved` or `Rejected`.

**Evidence hash.** A `bytes32` — the hash of a report, photographs, receipts — anchored on
chain while the documents stay off it. Same reasoning as modules 7 and 9.

**Pro-rata refund.** When a campaign is cancelled mid-way, each donor gets back their share
of what is *left*, not what they put in. Some money is already spent, and the loss is shared
in proportion.

**Pull payment.** Donors withdraw their own refunds. The contract never loops over a list of
addresses paying them out — see module 6 for why.

## How it works

```
Raising ──goal met──▸ Funded ──all milestones approved──▸ Completed
   │                    │
   └─deadline passed──▸ Failed          └─a milestone rejected──▸ Cancelled
       (full refunds)                        (pro-rata refunds)
```

| Function | Who | What |
| --- | --- | --- |
| `create(cause, goal, window, amounts[], what[])` | anyone | Milestones must sum **exactly** to the goal |
| `pledge(id, amount)` | anyone | Capped at what is still needed |
| `closeFailed(id)` | **anyone** | After the deadline, under goal |
| `submitEvidence(id, step, evidence)` | the beneficiary | In order, one at a time |
| `approveMilestone(id, step)` | `ARBITER_ROLE` | Releases that amount |
| `rejectMilestone(id, step, reason)` | `ARBITER_ROLE` | Cancels the campaign |
| `refund(id)` | each donor | Failed or Cancelled only |
| `refundable(id, donor)` | view | What you can take, without sending a transaction |

Bounds: window 5 minutes to 90 days; 2 to 5 milestones.

**Milestones must sum to the goal, exactly:**

```solidity
if (sum != goal) revert MilestonesDoNotSumToGoal(sum, goal);
```

No rounding, no slack, no leftover pot. If the arithmetic a donor checks is not the
arithmetic the contract does, the contract is lying by omission.

## The detail that matters

**Pledges are capped at the remaining amount:**

```solidity
uint256 remaining = c.goal - c.raised;
if (amount > remaining) revert Overfunded(remaining);
```

This is a small rule with a large consequence: `raised` can never exceed `goal`, so
`released` can never exceed what was pledged, so the pro-rata refund arithmetic cannot
overflow its own pot. Overfunding is a genuine mess in practice — do you return the surplus,
keep it, expand the project? — and the cleanest answer is to make it impossible.

**Anyone may close a failed campaign.** Not the beneficiary:

```solidity
function closeFailed(uint256 id) external {
    if (block.timestamp < c.deadline) revert TooEarly();
    c.state = State.Failed;
```

A beneficiary whose campaign flopped has no incentive to announce it, and if closing were
their decision the donors' money would sit there indefinitely. Any donor, or any passer-by,
can do it for the cost of gas. **Never make an action that protects users depend on the
party it protects them from.**

**The pro-rata refund:**

```solidity
uint256 owed = c.state == State.Failed
    ? pledged
    : (pledged * (c.raised - c.released)) / c.raised;
```

Failed means nothing was released, so everyone is made whole. Cancelled means milestone one
was paid and milestone two was rejected, so the remaining pot is shared in proportion to
what each donor contributed. Integer division rounds down, leaving dust in the contract —
tiny, deliberate, and worth understanding: rounding *against* the withdrawer is the only
safe direction, because rounding the other way lets the last donor out with more than
exists.

**The arbiter is the oracle, and this is the honest limitation.** Someone must look at the
evidence and decide whether the well was dug. The contract enforces the *process* — evidence
before payment, one stage at a time, public rejection with a stated reason — and has no
opinion on the *facts*. Module 14 attacks the same problem with a different tool, and does
not solve it either.

**Evidence is a hash.** The contract stores 32 bytes. A donor with the original report can
prove it is the one submitted; a donor without it has 32 meaningless bytes. Anchoring proves
integrity, never content.

## Walk through it

1. Create a campaign with a short window, a small goal, and three milestones summing to it.
2. From two other accounts, pledge — remember `approve` on TVD first.
3. Try to pledge more than remains. `Overfunded(remaining)` tells you the cap.
4. Reach the goal exactly. State flips to `Funded` in the same transaction.
5. **Beneficiary:** submit evidence for milestone 1.
6. Try to submit for milestone 3. `WrongStep()` — stages are ordered.
7. Instructor approves milestone 1. That amount, and only that, reaches the beneficiary.
8. Submit milestone 2 and have it **rejected**. The campaign cancels.
9. Each donor calls `refundable`, then `refund`. Notice the amounts are smaller than the
   pledges, and work out why by hand before reading the code.

Then the other path:

10. A second campaign that never reaches its goal. After the deadline, **a donor** calls
    `closeFailed`, then everyone refunds in full.

## What actually happened on chain

```
CampaignCreated(id: 2, beneficiary: 0x…, goal: 300e18, deadline: 1790…, cause: "new well")
Pledged(id: 2, donor: 0x…, amount: 200e18, raised: 200e18)
Pledged(id: 2, donor: 0x…, amount: 100e18, raised: 300e18)
GoalReached(id: 2, raised: 300e18)
EvidenceSubmitted(id: 2, step: 0, evidence: 0x…)
MilestoneApproved(id: 2, step: 0, amount: 100e18, arbiter: 0x…)
MilestoneRejected(id: 2, step: 1, reason: "photographs show no work", arbiter: 0x…)
Refund(id: 2, donor: 0x…, amount: 133333333333333333333)
```

Look at that last number: 133.333… TVD. Two hundred pledged, one third of the pot already
released, two thirds of two hundred returned. The dust from the division stays in the
contract for ever, and nothing in this design collects it — which is a reasonable choice and
should be a conscious one.

## When a plain database is better

For a registered charity in a functioning jurisdiction: the existing machinery is better.
Gift aid, regulated accounts, a complaints process, and the ability to reverse a fraudulent
card payment are not small things.

The milestone pattern earns its place when **donors and beneficiary share no institution** —
cross-border giving, disaster response into somewhere with no functioning regulator, funding
an anonymous developer — or when the point is that **the process itself is auditable by
anyone**, not by an auditor everyone must trust.

Be honest about what it costs: no tax relief, no chargebacks, no help if the beneficiary's
key is stolen, and an arbiter who is still just a person.

## What this does not fix

- **Whether the work was done.** The arbiter decides; the contract enforces that they must
  decide in public.
- **A captured arbiter.** One role, one human. Collusion with the beneficiary defeats
  everything here.
- **A dishonest beneficiary with plausible evidence.** Photographs can be of someone else's
  well.
- **Donor identity.** Anyone can pledge, including the beneficiary, to fake momentum.
- **The dust.** Small, permanent, unclaimable.

## Common mistakes

- **Releasing everything on funding.** That is Kickstarter, and it is the problem.
- **Pushing refunds in a loop.** One reverting recipient freezes every donor's money.
- **Letting the beneficiary declare failure.** They never will.
- **Milestones that do not sum to the goal.** Either money is stranded or the last milestone
  cannot be paid.
- **Rounding refunds up.** The last donor out finds an empty pot.
- **Forgetting `approve`.** Every ERC-20 flow in this repository starts with it.
- **Allowing overfunding, then improvising.** Decide up front.

## Security checklist

- [ ] Can `raised` ever exceed `goal`?
- [ ] Can a donor refund twice? Refund from a `Funded` campaign?
- [ ] Does the sum of all refunds ever exceed `raised - released`?
- [ ] Can the beneficiary skip a milestone, or resubmit an approved one?
- [ ] Can a campaign be closed as failed before its deadline?
- [ ] Can the arbiter release money to anyone but the beneficiary?
- [ ] What happens if the arbiter never rules — is the money stuck for ever?

## Extend it

1. Replace the single arbiter with the module 11 multisig, then with the module 12 DAO.
   Time both, and decide what a donor would actually prefer.
2. Add a donor veto: if holders of more than half the pledges object within a window, the
   milestone is rejected without an arbiter. Then work out how a whale abuses that.
3. Add a deadline per milestone, so a silent beneficiary cannot leave funds locked for ever.
   Decide where the money goes when it expires.
4. Let donors delegate their vote on milestones to someone who will actually read the
   evidence. You have just rebuilt module 12 for a narrower purpose.

## Further reading

- [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/5.x/access-control)
- [Pull over push payments](https://docs.soliditylang.org/en/latest/common-patterns.html#withdrawal-from-contracts)
- Read about assurance contracts and dominant-assurance contracts — the economics behind
  all-or-nothing funding, and older than any of this.

**Next:** [Module 14 · Insurer and oracle →](14-insurer.md)
