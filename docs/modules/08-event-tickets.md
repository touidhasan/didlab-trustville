# Module 8 · Event tickets

| | |
| --- | --- |
| **Contract** | `EventTickets.sol` |
| **Stop** | College |
| **Standard** | ERC-1155 (multi-token) |
| **Stamp** | Module 8 |

## The problem

Tickets have two failure modes that have never really been fixed: **counterfeits**, and a
**resale market** the organiser neither sees nor controls. Paper and PDF tickets are
copyable; platform tickets solve that by making the platform the only place a ticket can
exist, which solves counterfeiting by creating a monopoly.

There is also a boring engineering problem underneath. A university runs dozens of events a
year. Deploying a separate contract per event is expensive, slow, and leaves you with
dozens of addresses to track.

## The idea

**ERC-1155**: one contract holding many token types, each with its own id, supply and
balance. One deployment covers every event the college will ever run. Ticket 1 is the
Harvest Festival, ticket 2 the guest lecture, and a holder's balance of each is just a
number.

Tickets are ordinary transferable tokens — deliberately the opposite rule to module 2's
Passport, and a good pair to think about together.

## Key terms

**ERC-1155.** A standard for many token types in one contract. Balances are
`balanceOf(account, id)` rather than `balanceOf(account)`, and it supports batch operations.
Designed for games, where one contract might hold a thousand item types.

**Fungible within a type.** Two tickets to the same event are interchangeable, like ERC-20.
Tickets to different events are not, like ERC-721. ERC-1155 gives you both at once, which
is exactly what a ticket is.

**Burning to redeem.** Using a ticket destroys it. Destruction is how you prevent reuse,
and it is cheaper and clearer than a "used" flag on every ticket.

**Pull payments again.** Refunds and proceeds are withdrawn, not pushed — the same reasoning
as module 6.

## How it works

```solidity
struct EventInfo {
    address organiser;
    uint256 price;      // TVD per ticket
    uint64 startsAt;
    uint32 capacity;
    uint32 sold;
    uint32 redeemed;
    bool cancelled;
    string name;
}
```

| Function | Who | What |
| --- | --- | --- |
| `createEvent(name, price, capacity, startsAt)` | any resident | New ticket type |
| `buy(id, quantity)` | anyone | Mints tickets, takes TVD |
| `redeem(id, quantity)` | the holder | Burns them at the door |
| `cancel(id)` | the organiser | Before it starts; enables refunds |
| `refund(id)` | ticket holders | Only for a cancelled event |
| `withdrawProceeds(id)` | the organiser | Only after it has started |
| `uri(id)` | anyone | On-chain JSON metadata |

Two timing rules carry most of the safety:

- **Tickets cannot be bought after the event starts** — `EventStarted()`.
- **Proceeds cannot be withdrawn before it starts** — `EventNotStarted()`.

Together they mean an organiser cannot take the money and cancel. Until the event begins,
every ticket's money is still in the contract, so a cancellation can always fund refunds in
full.

That is a small amount of code doing a lot of work, and it is worth pausing on: the
protection comes from *sequencing*, not from a guarantee fund or a trusted escrow agent.

## The detail that matters

**Redemption burns.**

```solidity
_burn(msg.sender, id, quantity);
e.redeemed += quantity;
```

A ticket that has been used no longer exists. Compare with a "used" boolean: that needs a
per-ticket record, costs more gas, and leaves a token in the wallet that looks valid to any
tool not checking the flag.

**Transferability is the design decision.** Tickets move freely, so:

- A student who cannot attend can pass their ticket to a friend — no platform, no fee.
- A tout can buy fifty and resell them at a markup.

Both follow from the same property. The interesting question is not "how do we stop touts"
but "what are we willing to give up to stop them", because every mechanism costs the honest
buyer something: non-transferable tickets (you cannot give yours away), price caps (a grey
market forms), identity checks (queues and privacy).

Trustville chooses free transfer and says so plainly, rather than pretending the problem
does not exist.

## Walk through it

1. Create an event with a small capacity, a price, and a start time a few minutes ahead.
2. From a second account, buy two tickets. Check `balanceOf(account, id)`.
3. Transfer one to a third student. It moves like any token.
4. Try to withdraw the proceeds now. `EventNotStarted`.
5. Redeem a ticket. The balance drops and the supply falls.
6. Redeem it again. There is nothing left to burn.
7. On another event, cancel it before it starts and take a refund.

## What actually happened on chain

```
TransferSingle(operator, from: 0x0, to: buyer, id: 2, value: 2)   // ERC-1155 mint
TicketsBought(id: 2, buyer: 0x…, quantity: 2, cost: 20e18)
...
TransferSingle(operator, from: holder, to: 0x0, id: 2, value: 1)  // redeem = burn
```

ERC-1155 uses one event shape for mint, transfer and burn, distinguished by whether `from`
or `to` is the zero address. Reading balances from logs therefore means handling all three
cases — which the labs will have you do.

## When a plain database is better

For a university selling tickets to its own events: a database, every time. Cheaper,
private, instantly refundable, and it can enforce "one per student" because it knows who
students are.

ERC-1155 earns its place when tickets should be **transferable without the issuer's
involvement**, when holders want custody rather than an account on a platform, or when the
tickets need to work with other software — a wallet, a game, a contract that accepts them
as proof of attendance.

## What this does not fix

- **Touting.** Free transfer means resale.
- **The door.** Somebody must connect a wallet at the entrance; a burned ticket proves
  nothing about who is standing there.
- **Sybil buying.** One address, fifty tickets, or fifty addresses with one each.
- **The chargeback problem.** No mechanism exists for "the event was terrible".

## Common mistakes

- **Letting the organiser withdraw before the event.** Take the money, cancel, keep it.
- **Refunds in a loop over holders.** One reverting recipient freezes all refunds.
- **Using ERC-721 per ticket.** Works, costs far more, and gives you nothing for a
  fungible item.
- **Forgetting capacity checks.** Overselling is a contract bug, not a business decision.
- **Assuming `balanceOf` has one argument.** ERC-1155 takes an id too.

## Security checklist

- [ ] Can the organiser withdraw before the event starts?
- [ ] Can tickets be bought after it starts? After cancellation?
- [ ] Can a ticket be redeemed twice? Redeemed and then refunded?
- [ ] Does `sold` ever exceed `capacity`?
- [ ] After a cancellation, is the contract's balance always enough for every refund?
- [ ] Can a holder refund tickets they already redeemed?

## Extend it

1. Add a resale cap: transfers must go through a function that limits the price. Find the
   hole — direct `safeTransferFrom` still works — and decide what you would really have to
   restrict.
2. Add tiered tickets (student, staff, public) as separate ids in the same event, and
   notice how little code that takes with ERC-1155.
3. Award a passport stamp for *attending*, so redemption leaves a permanent record. Then
   ask whether that is a nice feature or a surveillance one.

## Further reading

- [ERC-1155](https://eips.ethereum.org/EIPS/eip-1155)
- [OpenZeppelin ERC1155](https://docs.openzeppelin.com/contracts/5.x/erc1155)
- Compare with ERC-721 and ERC-20, and be able to say when each is right.

**Next:** [Module 9 · Property deeds →](09-property-deeds.md)
