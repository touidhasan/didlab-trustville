# Modules 9–10 · Property deeds, Rent escrow

## The problem

Two problems that ruin people's lives, both about who controls a record and who controls
money. Deeds get forged, registries get edited, and in much of the world nobody can say with
certainty who owns a house. Security deposits are worse in miniature: the landlord holds the
tenant's money and decides alone whether to return it.

## Why a blockchain

| Need | Blockchain answer | When a database is better |
| --- | --- | --- |
| Ownership nobody can quietly rewrite | Token ownership, every transfer public and signed | A land registry with a functioning court behind it |
| Sell or inherit without asking a registrar | Transfer the token | Transfers that legally require review anyway |
| A deposit neither party controls | Contract holds it; release rules are code | Both sides trust the same escrow agent |
| Tenant gets money back without permission | After the claim window, one call and it is theirs | — |

## Design

```
PropertyDeeds  ERC-721: register(addressLine, docHash) → deed; certify() by the town
RentEscrow     offerLease → acceptLease (deposit in) → payRent* → claim | returnDeposit
VoteToken      wraps TVD 1:1 into vTVD (ERC20Votes) — voting power for the Council (D3b)
```

**The same standard, the opposite rule.** A deed is an ERC-721, exactly like the Passport
from module 2 — but the Passport blocks transfers and the deed depends on them. Put the two
side by side: a credential that could be sold would be worthless, and a title that could not
be sold would be useless. The standard is not the policy.

**Registration is a claim; certification is an endorsement.** Anyone can register "12 Mill
Lane" — the chain cannot check the real world. The town's `CERTIFIER_ROLE` marks the deeds it
vouches for, and **certification is cleared automatically on transfer**, because the town
vouched for a person holding a property, not for a token forever. That is the honest
boundary between what a ledger knows and what an institution knows.

**Escrow the disputed thing, not everything.** Rent goes straight to the landlord: it is
owed, so holding it would only add risk. The deposit is what people fight over, so only the
deposit sits in the contract. When the lease ends the landlord gets a fixed window to claim
against it, publicly and with a stated reason; if no claim arrives, the tenant takes it back
without anyone's agreement. That last part is what a paper tenancy cannot offer.

**A claim is still a dispute.** `resolveClaim` belongs to an arbiter (the town admin), who
can award any split up to the deposit. Code cannot tell whether a carpet was already stained.
Same honest limit as module 5 — and worth saying out loud to students, because "trustless"
gets oversold.

### The voting wrapper, ahead of the Council

`VoteToken` deposits TVD and returns vTVD 1:1, reversible at any time. It exists because a
plain ERC-20 cannot vote: counting needs balances *as they stood at a past block*, or anyone
could buy tokens after a proposal opens, vote, and sell.

Two things that catch out real DAOs, not just students:

1. **Wrapping is not voting power.** You must also `delegate` — to yourself if you want to
   vote yourself. Undelegated tokens count for nobody. `depositAndSelfDelegate()` does both,
   but do the two steps separately once, and watch `getVotes` stay at zero in between.
2. **Power is measured at the proposal's snapshot block.** Buying after that changes nothing,
   and selling after it does not remove your vote.

## Try it

1. **Register a property**, then ask the instructor to certify it. Transfer the deed to a
   classmate and look again: the certification is gone. Why should it be?
2. **Offer a lease** on your deed to a classmate, with rent and a deposit. They accept, and
   the deposit lands in the contract — check the contract's balance on the explorer.
3. **Pay rent** and note it goes straight to the landlord, not into escrow.
4. Wait for the lease to end, then the claim window to pass, and **take the deposit back**.
5. Run it again, but this time have the landlord **claim** part of the deposit with a reason.
   The instructor resolves it. Was the split fair? Who decided, and on what evidence?
6. Try the impossible: claim before the lease ends, claim after the window, take the deposit
   back during the window, let a property you do not own.

## Extend it

1. Require both signatures to end a lease early, with the deposit split by agreement.
2. Add automatic monthly rent due-dates and a late fee, and decide who enforces them.
3. Make certification expire after a year unless renewed, so the town's endorsement stays fresh.

## Security checklist

- [ ] Can anyone but the deed owner let a property?
- [ ] Can the landlord reach the deposit before the lease ends? Write the test.
- [ ] Can a claim exceed the deposit? Can it be filed twice?
- [ ] Does the tenant need anyone's cooperation to recover an unclaimed deposit?
- [ ] After transferring a deed mid-lease, who can claim the deposit — and should that be true?
- [ ] Does wrapping without delegating leave a student silently unable to vote?
