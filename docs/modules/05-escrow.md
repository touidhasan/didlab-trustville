# Module 5 · Escrow

| | |
| --- | --- |
| **Contract** | `TownEscrow.sol` |
| **Stop** | Market |
| **Standard** | None — a state machine holding ERC-20 |
| **Stamp** | Module 5 (awarded to the **buyer**) |

## The problem

Two strangers want to trade. Whoever moves first carries all the risk: pay first and the
goods may never arrive; ship first and the money may never come.

Every marketplace solves this the same way — a middleman holds the money. That works, and
it costs a percentage, and it means the middleman can freeze your funds, go out of business,
or decide your dispute by policy rather than fact.

## The idea

**The contract moves first.** The buyer pays into the contract, where neither party can
touch it. The seller ships knowing the money exists. The buyer confirms and the seller is
paid.

Then the two awkward cases, which are where the design actually lives:

- The buyer goes quiet. The seller can claim after a deadline.
- Something is genuinely wrong. The buyer disputes, and an arbiter decides.

## Key terms

**Escrow.** Funds held by a third party until conditions are met. Here the third party is
code.

**State machine.** The order is always in exactly one of a few states, and only certain
moves are allowed from each. Modelling this explicitly — rather than with a pile of
booleans — is what makes the contract auditable.

**Deadline / timeout.** A time after which someone gains a right they did not have.
Without one, a silent counterparty freezes funds for ever, and "for ever" is literal.

**Arbiter.** A role that can settle a dispute. It is a human, deliberately, and the
interesting question is what they can and cannot do.

## How it works

```
None → Funded → Released      (buyer confirms)
             → Refunded       (arbiter sides with buyer)
             → Released       (seller claims after the deadline)
             → Disputed → Released / Refunded   (arbiter decides)
```

| Function | Who | When |
| --- | --- | --- |
| `createOrder(seller, amount, productId, window)` | buyer | Pays in, sets the deadline |
| `confirmReceipt(id)` | buyer | Pays the seller |
| `claimAfterWindow(id)` | seller | Only after the deadline |
| `dispute(id)` | buyer | Only before the deadline |
| `resolve(id, paySeller)` | `ARBITER_ROLE` | Only from `Disputed` |

`window` is bounded: `MIN_WINDOW` one minute, `MAX_WINDOW` thirty days. Bounds rather than
a constant, so the same contract suits a lab and a real sale — and so nobody sets a
thousand-year window and traps the funds.

`productId` optionally links the order to module 4, which is how the town's modules
compose without depending on each other.

## The detail that matters

**What the arbiter can and cannot do:**

```solidity
function resolve(uint256 id, bool paySeller) external onlyRole(ARBITER_ROLE) {
    // ... pays either the seller or the buyer, in full
}
```

They choose *which of two parties* gets the money. They cannot:

- send it to a third address, including their own;
- change the amount;
- split it;
- act on an order that is not disputed;
- do anything at all once the order has settled.

That is a deliberately narrow power, and the narrowness is the security property. Compare
with a payment platform's dispute team, who can do all of those things and whose reasoning
you never see.

It is also worth noticing what remains: the arbiter is a single trusted human. The contract
removes the *custody* risk (nobody can run off with the money) while leaving a *judgement*
risk. Most real systems do the same, and are less honest about it.

**The timeout protects the seller, not the buyer.** A buyer who receives goods and never
confirms is the common failure, and without `claimAfterWindow` the seller's money sits for
ever. The dispute window is the buyer's counterbalance: dispute before the deadline and the
automatic claim is blocked.

## Walk through it

1. **Buyer:** create an order to a classmate.
2. Check the contract's TVD balance on the explorer. The money is in neither wallet.
3. **Seller:** try to take it. There is no function that lets you.
4. **Buyer:** confirm receipt. The seller is paid.

Then the timeout path:

5. Create a second order with a short window and do nothing.
6. After the deadline, the seller calls `claimAfterWindow`.

Then the dispute path:

7. Create a third order, dispute it before the deadline, and have the instructor resolve it.

## What actually happened on chain

```
OrderCreated(id: 3, buyer: 0x…, seller: 0x…, amount: 25e18, deadline: 1790…)
Transfer(from: buyer, to: escrow, value: 25e18)     // the ERC-20 moving in
...
Released(id: 3, to: seller, amount: 25e18)
Transfer(from: escrow, to: seller, value: 25e18)
Stamped(tokenId: …, moduleId: 5, by: escrow)
```

Note the buyer needed **two** transactions to create the order: `approve` on the token,
then `createOrder`. Users find this surprising every time; it exists so that a contract can
only take what you explicitly allowed.

## When a plain database is better

eBay and Stripe do this at enormous scale, with fraud detection, chargebacks and a phone
number to call. For most commerce they are simply better.

Escrow on a chain matters when: the parties are in different jurisdictions with no shared
platform; the platform itself is the risk; or the goods are on chain, in which case the
whole trade can settle atomically and escrow disappears into a swap.

Be honest about the cost side too. This escrow has no fraud detection, no identity, no
chargeback, and a dispute process consisting of one person with a role.

## What this does not fix

- **It does not know if the goods arrived.** `confirmReceipt` is the buyer saying so.
- **The arbiter is a single point of trust.** They cannot steal, but they can be wrong,
  biased, or unavailable.
- **A buyer who disputes everything** costs the seller time; nothing here penalises that.
- **Goods that are fine but not as described** are exactly the case where code has no
  opinion.

## Common mistakes

- **No timeout.** Funds locked for ever by a silent party. The single most common escrow
  bug.
- **Letting the arbiter choose the recipient.** Instant rug. Restrict to the two parties.
- **Sending before updating state.** Set the state first, then transfer — checks, effects,
  interactions.
- **Forgetting `approve`.** The order creation reverts with an allowance error that means
  nothing to a user unless you decode it.
- **Assuming ERC-20 transfers return true.** Some tokens do not. `SafeERC20` handles it,
  which is why the contract uses it.

## Security checklist

- [ ] Can the arbiter send funds anywhere other than the two parties?
- [ ] Can the seller claim before the deadline? Can the buyer dispute after it?
- [ ] Can an order be released twice?
- [ ] What happens if the buyer disputes and the arbiter never responds?
- [ ] Is the window bounded at both ends?
- [ ] Could a malicious token contract reenter during a transfer?

## Extend it

1. Replace the single arbiter with the module 11 multisig, then with the module 12 DAO.
   Time each. Which would you accept as a seller?
2. Add partial refunds — the arbiter splits the amount. What new abuse does that enable,
   and what would you add to contain it?
3. Add a seller bond, forfeited on a lost dispute, so disputes cost the wrong party
   something. Then work out how a buyer could exploit that.

## Further reading

- [OpenZeppelin SafeERC20](https://docs.openzeppelin.com/contracts/5.x/api/token/erc20#SafeERC20)
- [Checks-Effects-Interactions](https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern)

**Next:** [Module 6 · Sealed-bid auction →](06-sealed-bid-auction.md)
