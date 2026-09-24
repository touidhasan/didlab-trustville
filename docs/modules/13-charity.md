# Module 13 · Milestone crowdfunding

## The problem

You give £50 to a cause. Some weeks later there is a photograph and a thank-you email. Was
the well dug? Was your £50 part of it, or did it pay for the email?

Two separate failures hide inside that discomfort, and it is worth naming them before
writing any code:

1. **The campaign does not reach its goal**, but the money is already spent on the part of
   the job that was affordable. Half a well is worth nothing.
2. **The campaign reaches its goal** and the organiser is handed everything on day one,
   with the work still entirely in the future.

The usual answer to both is a platform: it holds the money, decides when to release it,
and charges four to eight per cent for doing so. That works. It also means the platform is
now the thing everyone has to trust, and it can change its rules, fail, or simply keep the
money while a dispute drags on.

## Why a blockchain — and why only partly

A contract can hold the pledges and enforce the two rules above without anybody's
permission, and every donor can read the rules before giving rather than taking them on
faith. No platform, no fee, no discretion about *who* gets refunded.

What it cannot do is tell whether the well exists. The contract sees a 32-byte hash. A hash
proves the report has not been altered since it was posted; it proves nothing about whether
the receipts inside it are real. Somebody still has to look.

So this module is deliberately honest about its seams: the money is trustless, the
judgement is not. The arbiter is a human role, and the interesting classroom question is
who should hold it — the town, the donors, a randomly drawn panel, or the DAO from module
12. Every answer has a failure mode, and a student who can name the failure mode of their
own design has understood the module.

A plain database would be fine for this if donors already trusted the organiser. That is
the honest comparison: this design buys you the case where they do not.

## Design

```
create(cause, goal, window, amounts[], what[])   milestones must sum to the goal
pledge(id, amount)                               capped at exactly what is still needed
closeFailed(id)                                  anyone, once the deadline passes
submitEvidence(id, step, hash)                   beneficiary only
approveMilestone(id, step)                       arbiter — releases one tranche
rejectMilestone(id, step, reason)                arbiter — stops the campaign
refund(id)                                       the donor takes their own money
```

| State | Means | Money |
| --- | --- | --- |
| Raising | goal not yet met, deadline not passed | locked |
| Funded | goal met | released one milestone at a time |
| Completed | every milestone approved | all paid out |
| Failed | deadline passed under goal | refundable in full |
| Cancelled | a milestone was rejected | the unreleased remainder is refundable pro rata |

Three decisions carry most of the design:

**Pledges are capped at the remaining amount.** A pledge that would overshoot the goal is
rejected with the exact remaining figure in the error. There is no surplus, so there is no
argument about who owns it and no arithmetic a donor has to trust.

**Every payment is a pull.** Refunds are claimed by the donor, one transaction each. The
tempting alternative — loop over the donors and pay them all — puts every donor's money at
the mercy of the least cooperative one: a single recipient whose `transfer` reverts freezes
the entire loop, permanently. This is the shape behind the famous reentrancy exercises, and
avoiding it is a habit worth forming before it is a vulnerability worth exploiting.

**Approved tranches stay paid.** When a campaign is cancelled at milestone 2, the donors
get back what was never released, not what was never spent. The work behind milestone 1 was
done and accepted; clawing it back would make the approval meaningless. The refund formula
is therefore `pledged × (raised − released) / raised`, and integer division means the last
few wei stay in the contract as dust — a real and unavoidable property worth showing
students rather than hiding.

## Try it

1. **Open a campaign** with two milestones, a short window, and a small goal.
2. **Pledge from a second account.** Try to pledge more than is left: the error tells you
   exactly how much the campaign still needs.
3. **Meet the goal**, then check the beneficiary's balance. It has not changed. Meeting the
   goal is not being paid.
4. **Submit evidence** for milestone 1 as the beneficiary, and approve it as the arbiter.
   Exactly one tranche moves; watch the contract's balance on the explorer.
5. **Reject milestone 2.** Then, from each donor account, take the refund and check the
   arithmetic yourself: two donors who gave 200 and 100 get back 133.33 and 66.66 of the
   remaining 200.
6. **Run a campaign that fails.** Let the deadline pass, call `closeFailed` from an account
   with no stake in it at all — that is allowed on purpose — and take the full refunds.
7. Try to refund twice. Try to approve your own milestone. Try to pay a milestone that has
   no evidence. Each refusal is a line of the design.

## Extend it

1. **Replace the arbiter with the DAO.** Make `ARBITER_ROLE` the Timelock from module 12,
   so releasing a tranche needs a vote. Time a release. Is it better?
2. **Add a deadline per milestone.** If the beneficiary posts no evidence within it, donors
   can cancel without needing the arbiter at all. Who does this protect, and from whom?
3. **Let a donor withdraw while the campaign is still raising.** Easy to add, and it
   changes the game theory: pledges become reversible signals rather than commitments.
   Argue for or against.

## Security checklist

- [ ] Can the beneficiary reach any money without an approval?
- [ ] Can the arbiter send a tranche anywhere other than the beneficiary, or change its size?
- [ ] Can a donor be refunded twice, or refunded more than they pledged?
- [ ] If one donor's address cannot receive tokens, does anybody else's refund break?
- [ ] After a cancellation, does refunded + released equal raised, up to dust?
- [ ] Can anyone but the beneficiary post evidence? Can evidence be replaced after approval?
- [ ] What happens to a campaign whose arbiter loses their key?
