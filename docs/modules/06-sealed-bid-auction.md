# Module 6 · Sealed-bid auction

| | |
| --- | --- |
| **Contract** | `SealedAuction.sol` |
| **Stop** | Market |
| **Pattern** | Commit–reveal |
| **Stamp** | Module 6 |

## The problem

A sealed-bid auction means nobody sees anyone else's bid until bidding closes. That is the
point: you bid what the item is worth to you, not one pound more than the person in front.

On a public chain, **everything is visible**. Contract storage is readable by anyone.
Transaction data is readable before it is even mined, while it sits in the mempool. Writing
`bid(100)` publishes your bid to the world, and on a public network a bot will outbid you in
the same block for slightly more.

So a naive on-chain auction is not sealed, it is a live auction with extra steps.

## The idea

Bid in two phases.

**Commit.** Send `keccak256(yourAddress, amount, salt)` — a fingerprint of your bid. It
reveals nothing, and you cannot change it afterwards.

**Reveal.** Send the amount and salt. The contract recomputes the hash and checks it
matches what you committed. Now your bid counts, and now everyone can see it — but the
commit phase is over, so nobody can react.

This is **commit–reveal**, and once you have seen it you will recognise it everywhere:
sealed auctions, on-chain games, voting, randomness, domain registration.

## Key terms

**Salt.** A random value mixed into the hash. Without it, bids are guessable: there are
only so many plausible amounts, and an attacker hashes them all until one matches. The salt
makes the input space too large to search. Reuse a salt across auctions and you reintroduce
the problem.

**Front-running.** Seeing a pending transaction and getting yours in first. On a public
chain this is an industry, not a hypothetical. DIDLab's four known validators make it far
less pressing here — which is itself worth noticing, since it means this chain is a gentler
teacher than reality.

**Pull payment.** The contract does not send refunds; it records what it owes and lets
people withdraw. This is the pattern that stops one bad recipient breaking everyone else.

## How it works

```
commit phase          reveal phase           after
──────────────  ▸  ──────────────────  ▸  ─────────
commitBid()        revealBid()             settle()
                                           withdrawRefund()
```

| Function | Who | When |
| --- | --- | --- |
| `createAuction(title, productId, commitSecs, revealSecs)` | any resident | Sets both phases |
| `commitBid(id, commitment)` | anyone but the seller | Commit phase only, once |
| `revealBid(id, amount, salt)` | the committer | Reveal phase only |
| `settle(id)` | anyone | After the reveal phase |
| `withdrawRefund()` | any outbid bidder | Any time |
| `hashBid(bidder, amount, salt)` | view helper | Builds the commitment for you |

Phases are bounded: `MIN_PHASE` 30 seconds, `MAX_PHASE` 7 days.

**The commitment includes the bidder's address:**

```solidity
keccak256(abi.encodePacked(msg.sender, amount, salt))
```

Without that, anyone could copy your commitment and submit it as their own. They would not
know what it meant — but they would be committed to the identical bid, and could reveal it
the moment you did. Binding the hash to the address makes a copied commitment unrevealable
by anybody else.

**Tokens move at reveal, not commit.** Committing is free, which is what keeps the commit
phase cheap and private. At reveal the contract pulls the bid amount; a losing bid is
immediately credited to `refunds` for later withdrawal, and an outbid leader's funds move
to `refunds` when someone overtakes them.

## The detail that matters

**Withdrawals are pull, not push:**

```solidity
function withdrawRefund() external {
    uint256 owed = refunds[msg.sender];
    if (owed == 0) revert NothingToWithdraw();
    refunds[msg.sender] = 0;      // zero BEFORE transferring
    token.safeTransfer(msg.sender, owed);
}
```

The tempting alternative is to refund every loser inside `settle`. Then one recipient whose
`transfer` reverts — a contract with no receive function, a token with a blocklist — takes
the whole settlement down with it, permanently, for everybody.

Note also the ordering: the balance is zeroed *before* the transfer. If the transfer
somehow re-entered `withdrawRefund`, the second call would find zero. Effects before
interactions, every time.

**Committing and not revealing is free here.** A bidder who commits a huge bid and never
reveals costs themselves nothing and may deter others. Real designs require a deposit at
commit time, forfeited if you fail to reveal. This contract does not — deliberately, so the
gap is visible — and closing it is the first exercise.

## Walk through it

1. Create an auction with short phases.
2. From a second account, call `hashBid(yourAddress, amount, salt)` to build a commitment,
   then `commitBid`. **Write down the amount and salt** — without both, you cannot reveal,
   and there is no recovery.
3. During the commit phase, look at the auction's storage on the explorer. Try to work out
   what anyone bid. You cannot.
4. Reveal from each bidder. Watch `BidRevealed` and which one is leading.
5. Settle. The seller is paid the high bid.
6. Losers call `withdrawRefund`.

Then break it on purpose: commit a bid and never reveal. Note what it cost you.

## What actually happened on chain

```
BidCommitted(id: 2, bidder: 0x…)                        // no amount anywhere
BidRevealed(id: 2, bidder: 0x…, amount: 40e18, leading: true)
Settled(id: 2, winner: 0x…, amount: 40e18)
```

The commit event deliberately carries no amount. Everything a bidder needs to reveal is
kept by the bidder, not the contract — which is why losing your salt is unrecoverable.

## When a plain database is better

For most auctions, obviously: eBay is cheaper, faster, understood by everybody, and can
run a genuine sealed-bid process by simply not showing the bids.

Commit–reveal matters when **the auctioneer is the party you cannot trust** — when they
might leak bids to a favoured buyer, insert a shill, or adjust the result. A database can do
sealed bids; it cannot prove it did.

## What this does not fix

- **Non-revealers.** Free to grief here.
- **Timing analysis.** Commit transactions are public. Who bid, and when, leaks even though
  amounts do not — and on a chain with few participants, that can be enough.
- **Collusion.** A bidding ring is invisible to the contract.
- **The seller bidding via another address.** Shill bidding needs identity to prevent, and
  identity does not exist here.

## Common mistakes

- **Omitting the address from the commitment.** Commitments become copyable.
- **Reusing a salt**, or using a predictable one like `1`. Brute-forceable.
- **Refunding in a loop.** One reverting recipient freezes everyone.
- **Losing the salt.** Tell users loudly, at commit time, in the interface.
- **Phases that are too short.** Miss the reveal window and the bid is lost.

## Security checklist

- [ ] Can a commitment be copied and submitted by someone else?
- [ ] Can a bid be revealed after the reveal phase? Can it be revealed twice?
- [ ] What does it cost to commit and never reveal?
- [ ] Can `settle` be called twice? Before the reveal ends?
- [ ] Can a refund be withdrawn twice, or re-entered?
- [ ] Can the seller bid on their own auction?

## Extend it

1. Require a deposit at commit time, forfeited on a failed reveal. Decide where the
   forfeit goes, and what a malicious seller could do with that rule.
2. Make it a **second-price** (Vickrey) auction: the winner pays the second-highest bid.
   Work out what that changes about how people bid.
3. Add a reserve price the seller commits to at creation and reveals at settlement. Now the
   seller has a commitment to honour too.

## Further reading

- [Commit–reveal schemes](https://ethereum.org/en/developers/docs/smart-contracts/security/)
- *Flash Boys 2.0* — the paper that named front-running on chain.
- Vickrey auctions, and why theoretical elegance and practical use diverge.

**Next:** [Module 7 · Verifiable certificates →](07-verifiable-certificates.md)
