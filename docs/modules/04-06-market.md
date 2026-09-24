# Modules 4–6 · Provenance, Escrow, Sealed-bid auction

## The problem

Trustville's market is full of strangers. A buyer cannot tell where the honey came from,
and neither side wants to move first on payment. At auction, every bid is public the moment
it is made, so the last person to look always wins.

## Why a blockchain

| Need | Blockchain answer | When a database is better |
| --- | --- | --- |
| A custody trail no party can quietly rewrite | Append-only events, each signed by whoever handed the goods on | One company tracking its own inventory |
| Payment neither side controls | Escrow contract holds the funds; code decides when they move | A marketplace everyone already trusts to hold money |
| Bids that stay secret until the close | Commit–reveal: publish a hash, reveal later | A sealed-bid process run by a trusted auctioneer |

**The honest limit of provenance.** A chain proves a record has not changed since it was
written. It cannot prove the record was true. Anyone can register "Miller farm" for a jar
of supermarket honey. Closing that gap needs attestation at the point of capture — an
identity or a device signing for the claim — which is a much harder problem than storage.
Ask students where they would put that boundary.

## Design

```
ProductRegistry   register(name, origin, docHash) → id; transferCustody(id, to, note)
TownEscrow        createOrder → confirmReceipt | claimAfterWindow | dispute → resolve
SealedAuction     createAuction → commitBid → revealBid → settle; withdrawRefund
Stamping          shared base: awards a passport stamp when it safely can
```

Three patterns worth pausing on:

1. **State before transfer.** Every contract sets its state (`Released`, `refunds[x] = 0`)
   *before* moving tokens. Reversing those two lines is the classic reentrancy bug.
2. **Pull, not push, refunds.** Losing bidders call `withdrawRefund()` themselves. Pushing
   tokens to a list of losers is how auctions get permanently stuck on one bad transfer.
3. **Escrow needs a judge.** `resolve()` is held by an arbiter (the town admin). Code can
   enforce "nobody takes the money unilaterally", but it cannot tell whether a box arrived
   empty. That is an honest limit, not a missing feature.

### A bug we hit, and why it matters

The first version stamped passports with `try passport.stamp(...) {} catch {}`, so a
missing role could never break the module. It worked in unit tests and failed in the
browser: no stamps were ever awarded.

A caught failure still leaves the transaction successful, so `eth_estimateGas` binary-
searches down to the cheapest gas limit where it "succeeds" — the one where the inner call
runs out of gas and gets caught. Estimation and execution agreed with each other, and both
were wrong.

The fix is in `Stamping.sol`: check the preconditions (has a passport, not already stamped,
role granted) with view calls, then call `stamp` unconditionally. Nothing is swallowed, so
estimation sees the real cost. **Lesson: swallowing errors does not make code robust, it
makes failures invisible.**

## Try it

1. **Register a product**, then hand custody to a classmate. Watch `CustodyTransferred`
   and note that only the current holder can move it on.
2. **Pay into escrow.** Two transactions: approve, then fund. Look at the token balance of
   the escrow contract on the explorer — your money is sitting there, not with the seller.
3. **Confirm receipt** and watch it move. Then run a second order and try to `dispute` it.
4. **Start an auction.** Commit a bid, then open DevTools and look at the transaction: your
   amount is nowhere in it, only a hash. Reveal in the second phase.
5. **Lose on purpose.** Bid low against a classmate, reveal, then withdraw your refund.
6. **Break it:** reveal with the wrong amount, commit twice, bid on your own auction, reveal
   after the deadline. Read the error each time.

## Extend it

1. Require a deposit at commit time, so a bidder cannot walk away for free. What size?
2. Make custody transfer require the recipient to accept, so nobody can push goods onto you.
3. Let the escrow release partially (a refund for damaged goods) rather than all-or-nothing.

## Security checklist

- [ ] Is state written before every token transfer?
- [ ] Can any function be called twice to double-spend? Write the test.
- [ ] Who can call `resolve`, and what stops them from taking the funds?
- [ ] What happens if a bidder never reveals? Is anything left stuck in the contract?
- [ ] Does your UI ever rely on a caught error to decide something?
