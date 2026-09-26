# Module 10 · Rent escrow

| | |
| --- | --- |
| **Contract** | `RentEscrow.sol` |
| **Stop** | Housing |
| **Standard** | None — a state machine over ERC-20 and ERC-721 |
| **Stamp** | Module 10 (awarded to the **tenant** on acceptance) |

## The problem

A tenancy deposit is money the tenant owns, held by the landlord, returnable at the end if
nothing is damaged. The landlord decides whether anything is damaged.

That is an obvious conflict of interest, and the numbers show it: deposit disputes are among
the most common consumer complaints in any country with a rental market. Several countries
responded with statutory deposit protection schemes — a third party holds the money,
precisely because the landlord should not.

## The idea

The contract is the protection scheme. It holds the deposit from the moment the tenant
accepts the lease, and neither party can touch it.

The end-of-tenancy rules are where the design lives:

- The landlord may claim some or all of the deposit, **in public, with a stated reason**,
  within a fixed window after the lease ends.
- If they do not claim within that window, the tenant simply takes the money back. Nobody
  has to agree, and the landlord cannot stall.
- If they do claim, it becomes a dispute and a human arbiter splits it.

Note the default: **silence returns the money to the tenant.** In most real disputes, the
default runs the other way, and that asymmetry is most of the problem.

## Key terms

**Deposit.** Money held as security against damage or unpaid rent. It remains the tenant's
property throughout; holding is not owning.

**Claim window.** A bounded period after the lease ends during which the landlord may make a
claim. Bounded in both directions: `MIN_CLAIM_WINDOW` two minutes, `MAX_CLAIM_WINDOW`
thirty days.

**State machine, again.** `None → Offered → Active → Settled`, with a detour through
`Claimed`. Module 5 introduced the pattern; here it carries two assets and a second
contract.

**Composition.** This contract reads `PropertyDeeds` (module 9) to check who may offer a
lease. Modules that build on each other, through interfaces rather than inheritance, is how
real systems are assembled.

## How it works

```
Offered ──accept──▸ Active ──(window passes, tenant acts)──▸ Settled
                      │
                      └──landlord claims──▸ Claimed ──arbiter──▸ Settled
```

| Function | Who | When |
| --- | --- | --- |
| `offerLease(deedId, tenant, rent, deposit, term, claimWindow)` | the deed owner | Creates the offer |
| `acceptLease(id)` | the named tenant | Pays the deposit in |
| `payRent(id)` | the tenant | While active, before the end |
| `claimDeposit(id, amount, reason)` | the landlord | After the end, inside the window |
| `returnDeposit(id)` | the tenant | After the window, if no claim |
| `resolveClaim(id, toLandlord)` | `ARBITER_ROLE` | Only from `Claimed` |

Bounds: `MIN_TERM` five minutes, `MAX_TERM` 365 days.

**Rent is not escrowed.** `payRent` transfers straight from tenant to landlord:

```solidity
if (l.rent > 0) token.safeTransferFrom(msg.sender, l.landlord, l.rent);
```

Only the deposit is held. This is deliberate and correct — rent is payment for a service
already received, and escrowing it would give the tenant an unearned lever. Being clear
about *which* money is in dispute is half of designing an escrow.

## The detail that matters

**Ownership of the deed is checked at offer time, and only then:**

```solidity
address owner = deeds.ownerOf(deedId);
if (msg.sender != owner) revert NotTheDeedOwner(owner);
```

After that, the lease stands on its own. Sell the house mid-tenancy and the lease does not
follow — the old landlord still receives rent and still controls the deposit claim.

That is a bug if you think of this as a property system, and a *lesson* if you think of it
as a teaching contract: **a snapshot check is not an ongoing relationship.** Real leases
bind successors in title; that is a legal concept with no on-chain equivalent unless you
build one. Fixing it is the first extension, and there is no clean fix — you must choose
between reading `ownerOf` on every call (the landlord changes underneath the tenant) and
freezing the landlord at offer time (what the contract does). Both are defensible; neither
is what the law does.

**The claim must carry a reason**, stored and emitted:

```solidity
l.claimReason = reason;
emit DepositClaimed(id, msg.sender, amount, reason);
```

The contract cannot judge the reason. What it can do is make the reason permanent, public,
and attributable — so a landlord who claims "cleaning" on every tenancy leaves a visible
pattern. That is a weaker mechanism than adjudication, and a real one: much of what
regulation achieves is simply making behaviour legible.

**The tenant's exit needs nobody's cooperation.** `returnDeposit` requires only that the
window has closed. No landlord signature, no arbiter, no admin. Every escrow should be
examined for the question "what if the counterparty simply stops responding?", and this is
the answer to it.

## Walk through it

1. Register a property in module 9, so you hold a deed.
2. Offer a lease to a classmate with a short term and a short claim window.
3. **Tenant:** accept. The deposit leaves your wallet — check the contract's balance.
4. **Tenant:** pay rent a couple of times. It goes straight to the landlord, not the
   contract.
5. Wait for the term to end, then the claim window. **Tenant:** `returnDeposit`.

Then the disputed path:

6. A second lease. When it ends, the landlord claims part of the deposit with a reason.
7. The tenant cannot take it back now — `WrongState(Claimed)`.
8. The instructor resolves the split. Both sides are paid in the same transaction.

## What actually happened on chain

```
LeaseOffered(id: 2, landlord: 0x…, tenant: 0x…, rent: 5e18, deposit: 20e18, endsAt: 1790…)
LeaseAccepted(id: 2, tenant: 0x…, deposit: 20e18)
Stamped(tokenId: …, moduleId: 10, by: rentEscrow)
RentPaid(id: 2, tenant: 0x…, amount: 5e18, paymentNumber: 1)
...
DepositClaimed(id: 2, landlord: 0x…, amount: 8e18, reason: "carpet")
ClaimResolved(id: 2, arbiter: 0x…, toLandlord: 3e18, toTenant: 17e18)
```

`rentPaid` is a counter, not a schedule. The contract does not know whether rent is monthly
or weekly, or whether a payment is late — it counts. Ask yourself what it would take to
enforce a schedule, and whether you would want a contract that can declare you in arrears.

## When a plain database is better

For residential tenancy, the statutory schemes are better: they have adjudicators who look
at photographs, they are free to the tenant, they are backed by law, and they can be
appealed.

Escrow on a chain becomes interesting for **short lets between strangers with no shared
platform**, for **equipment or venue hire** where the sums are small and a platform's cut is
not, and as a **transparency layer** — even a scheme that keeps human adjudication can
benefit from claims being publicly logged rather than buried in a ticketing system.

## What this does not fix

- **Whether the carpet was actually stained.** No photograph is on chain, and a hash of one
  proves only that it existed.
- **The arbiter.** One human, one role, the same honest limitation as module 5.
- **Landlord changes.** As above.
- **Rent arrears.** The contract counts payments; it has no view on whether they were due.
- **Eviction, repairs, habitability** — everything that makes tenancy law long.

## Common mistakes

- **Escrowing the rent as well as the deposit.** Gives the tenant a hostage.
- **Letting the landlord claim with no deadline.** The deposit never comes back.
- **Requiring the landlord to agree to the return.** Reintroduces exactly the problem the
  contract exists to solve.
- **Allowing a claim larger than the deposit.** `ClaimTooLarge` exists for a reason; without
  it, `deposit - toLandlord` underflows or the split is nonsense.
- **Forgetting that the tenant must `approve` the token first.** Two transactions, and the
  first failure students hit.
- **Reading `ownerOf` inside a pranked call in tests.** See the note in the repository's
  test files; this has bitten us more than once.

## Security checklist

- [ ] Can the landlord claim after the window? Can the tenant withdraw during it?
- [ ] Can `resolveClaim` send funds anywhere other than the two parties?
- [ ] Does `toLandlord + toTenant` always equal the deposit exactly?
- [ ] Can a lease be accepted twice, or by someone other than the named tenant?
- [ ] Can rent be paid after the lease ends? Should it be?
- [ ] What happens if the deed is transferred or burned mid-lease?
- [ ] If the arbiter never resolves a claim, what is the tenant's recourse?

## Extend it

1. Make the lease follow the deed: read `ownerOf` at claim time instead of storing the
   landlord. Then work out how a landlord could abuse that by selling the deed to themselves
   at the right moment.
2. Add a rent schedule with due dates and an arrears flag, and then argue about whether a
   contract should be able to brand someone a bad tenant permanently.
3. Escrow a photograph hash with each claim, so the evidence is at least timestamped. Note
   carefully what that does and does not prove.
4. Replace the single arbiter with the module 11 multisig, and measure how much slower the
   dispute path becomes.

## Further reading

- [OpenZeppelin SafeERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#SafeERC20)
- [Checks-Effects-Interactions](https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern)
- Read how a statutory tenancy deposit scheme in your own country handles disputes, and
  list what it does that this contract cannot.

**Next:** [Module 11 · Multisig treasury →](11-multisig-treasury.md)
