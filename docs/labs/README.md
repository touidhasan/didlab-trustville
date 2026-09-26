# Trustville labs

Six labs. In each one you ship a feature into a working dApp: contract, tests, interface,
and a pull request that survives review.

This is not a tour of the town. You will have used the site in week one and that is the
end of it as an activity. From lab 1 onward Trustville is the codebase you work in, and
the standard is the one applied to a junior full stack engineer in their first months:
**does it work, does it fail safely, is it tested, and can someone else maintain it?**

| Lab | You ship | The skill being hired for |
| --- | --- | --- |
| [1](lab-1-shipping-your-first-change.md) | A working dev environment and a first merged PR | Reading an unfamiliar codebase and changing it safely |
| [2](lab-2-reading-the-chain.md) | An activity feed built from event logs | Getting data out of a chain without an indexer |
| [3](lab-3-writing-transactions.md) | A certificate issue-and-verify flow | The transaction lifecycle, and every way it fails |
| [4](lab-4-a-vertical-slice.md) | A contract change and the interface for it | Contract and frontend as one change |
| [5](lab-5-state-machines-and-time.md) | The governance interface, done properly | Modelling a contract's state machine in a UI |
| [6](lab-6-money-prices-and-failure.md) | Trading, borrowing, and an attack write-up | Handling money in an interface, and reporting when it goes wrong |

## The standard

Every lab is delivered as a **pull request against your fork**. It is marked the way a PR
is marked at work.

**Definition of done.** A PR is finished when:

- CI is green — contracts build optimized, tests pass, `forge fmt` is clean, the app
  builds, and no secret is in the diff.
- Tests cover the happy path **and each way the thing can fail**. A test suite that only
  proves the good case is not evidence.
- The interface handles: wallet rejected, transaction reverted, wrong network, insufficient
  funds, and a pending transaction. A spinner that never resolves is a bug, not a state.
- Custom errors are decoded and shown as something a user can act on. `0x7939f424` is not
  an error message.
- The PR description explains **why**, not what. The diff already says what.
- A peer has reviewed it and you have addressed the comments. "Addressed" includes
  disagreeing, with a reason.

**Incidents.** Each lab also needs one write-up in `docs/incidents/` when something breaks
— a failed deploy, a wrong address, a transaction that did something you did not intend.
Use [the template](../INCIDENT.md). Over six labs, "nothing broke" will not be true.

Blameless means naming systems rather than people. "I forgot to grant the role" describes
the outcome. "The deploy script printed the grant command and nothing verified it had been
run, so a missing role looked identical to a working deployment" describes the cause, and
it produces a fix.

## How you work

```bash
git checkout -b lab-3-certificates
# ... build it ...
cd contracts && FOUNDRY_PROFILE=test forge test
cd .. && npm run build
git push -u origin lab-3-certificates
# open the PR, request a reviewer
```

Small commits with honest messages. Rebase rather than merge-commit your own branch. If CI
is red, it is red for you too — do not ask a reviewer to look at a broken branch.

**Review is half the job.** You will review a classmate's PR in every lab, and that review
is marked. A review that says "looks good" is worth nothing; the ones that count find a
missing failure state, an unhandled revert, or a design that will not survive its second
requirement.

## How it is marked

| | |
| --- | --- |
| It works — meets the spec, CI green | 30% |
| It fails well — every failure state handled and shown honestly | 25% |
| Tests — happy path and failure paths, meaningful assertions | 20% |
| The PR itself — description, commits, reviewability | 15% |
| Your review of someone else's PR | 10% |

Note what is not on that list: using the site, and finishing quickly. The passport stamps
record that you performed a transaction. They are a warm-up, not a grade.

## Before lab 1

- Node 20+, Foundry, git, a GitHub account.
- MetaMask with a **fresh wallet made for this course**, funded from the faucet.
- Your own fork of the repository, cloned, with `npm run local` working.

If `npm run local` does not give you a working town on localhost, you cannot start lab 1.
Fix that first — and if fixing it takes you two hours, that was lab 0 and it was not wasted.

## A note on the chain

DIDLab is a permissioned chain with free gas and instant finality. That is a teaching
convenience and also a distortion: on a public chain your transaction competes for space,
costs real money, and may be front-run by someone reading the mempool. Where a design
depends on that difference, the labs say so. Do not learn habits here that will cost
somebody money later.
