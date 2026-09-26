# Lab 4 · A vertical slice

**Deliverable:** a pull request: contract change, tests, deployment, interface ·
**Time:** two hours, and it will not all fit

The first lab where you change a contract. A full stack dApp developer is not someone who
writes Solidity *or* React; it is someone who can take a requirement through both and know
which side each problem belongs on.

## The requirement

> Tenants who have paid every month should be able to renew a lease without repaying the
> deposit. At the moment the lease ends, the deposit is settled, and a renewal means
> finding that money again — which for many tenants is the reason they cannot move and the
> reason they cannot stay.

That is the requirement as a product owner would give it: a real problem, no
implementation. The design is yours.

## Your job

1. **Design it.** Write the design in the PR description *before* the code: what changes in
   `RentEscrow`, what new state, who can call what, and what the new failure cases are.
2. **Implement it** in `contracts/src/RentEscrow.sol`.
3. **Test it** in `contracts/test/Housing.t.sol`.
4. **Deploy it** — update the deployment script, run `npm run sync-abi`, and note in the PR
   what a real redeploy of this contract would owe (there are two follow-ups, and both fail
   silently; lab 1's reading should have shown you where they are documented).
5. **Build the interface** in `Housing.jsx`.

## Constraints that are not negotiable

- **The deposit stays where neither party controls it.** A renewal that pays the deposit
  out and takes it back is not a renewal; it is two transactions and a window where the
  tenant's money is somewhere it should not be.
- **Neither party can renew alone.** Work out what "agreement" means on chain, and
  implement it. There is more than one right answer; there are many wrong ones.
- **Existing leases keep working.** Your change must not alter the behaviour of a lease
  already in progress. Every existing test must still pass, unchanged.
- **Durations stay bounded.** The contract's `MIN_TERM` and `MAX_TERM` exist so the same
  code works for a lab and a homework week. Do not bypass them.

## Acceptance criteria

- [ ] A design section in the PR that a reviewer could have implemented from.
- [ ] The contract compiles optimized and its deployed size is reported (`forge build
      --sizes`).
- [ ] New tests cover: the happy path, each party trying to renew alone, renewing a lease
      that has already ended, renewing one that was claimed against, and at least one fuzz
      test over the amounts or durations.
- [ ] **All existing Housing tests pass unchanged.** If you had to change one, the PR
      explains why — and "it was in the way" is a finding about your design.
- [ ] `npm run sync-abi` run and the result committed.
- [ ] The interface offers renewal only when it is actually possible, and says why when it
      is not.
- [ ] CI green.

## Deployment notes

You are changing a deployed contract. In your PR, answer:

- Existing leases live in the **old** contract. What happens to them when you deploy the
  new one? Is that acceptable, and who decides?
- What would the migration be if this were real money?

This is the question that separates a student exercise from engineering. Most on-chain code
cannot be changed after deployment, so "we will fix it in the next release" is not
available, and the design has to carry that weight from the start.

## Common ways this goes wrong

- **A renewal that pays out and re-collects.** Re-read the first constraint.
- **A one-sided renew.** If the landlord can extend a lease unilaterally, you have built a
  trap. If the tenant can, you have built a different one.
- **Timestamp arithmetic that overflows or wraps.** `endsAt + term` is a `uint64`. Prove it
  is safe or make it safe.
- **Silently changing an existing test to make it pass.** A reviewer will diff the test
  file first. So will an employer.
- **Forgetting `sync-abi`.** The app builds against a stale ABI and the new function is
  simply absent, with no error anywhere. CI catches this; notice that it does.

## Out of scope

No changes to `PropertyDeeds`. No new tokens. No UI redesign — add to the existing card.

## Hand in

1. The PR with its design section, CI green, reviewed and approved.
2. Your review of someone else's PR. Read their tests before their contract, and check
   whether both parties really have to agree.
3. An incident write-up. This is the lab where something will break — a stale ABI, a
   missing role, a deploy that half-worked. Write it up properly.
