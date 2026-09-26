# Module 4 · Product provenance

| | |
| --- | --- |
| **Contract** | `ProductRegistry.sol` |
| **Stop** | Market |
| **Standard** | None — a registry with a custody chain |
| **Stamp** | Module 4 |

## The problem

A jar of honey says "Miller Farm" on the label. The label is a sticker. Anyone can print
one.

Supply chains run on documents that assert origin and custody, and the documents are
produced by whoever benefits from them. This is the problem that gets blockchains sold to
industry more than any other — usually with more confidence than it deserves.

## The idea

Record the product's creation and every change of custody on chain, so the *chain of
claims* is public, timestamped and append-only. Nobody can quietly insert a step, backdate
a handover, or remove an inconvenient holder.

What you get is a record that cannot be edited afterwards. What you do not get is any
assurance that the record was true when it was written. Keeping those two apart is the
entire point of this module.

## Key terms

**Provenance.** The documented history of an object: where it came from, who held it, in
what order.

**Custody chain.** The sequence of holders. Each transfer is a transaction signed by the
current holder, so the chain is a series of signed claims rather than one party's ledger.

**Append-only.** Entries are added, never changed or removed. The chain gives this for
free; achieving it in a database takes deliberate work and a trusted operator.

**The oracle problem (early sighting).** The gap between a physical fact and what a contract
knows. Module 14 confronts this directly; here it appears in a quieter form, and most
real-world supply chain projects fail exactly here.

## How it works

```solidity
struct Product {
    address creator;   // who registered it
    address holder;    // who has it now
    uint64 createdAt;
    uint32 transfers;  // how many times it changed hands
    string name;
    string origin;
    bytes32 docHash;   // certificate, lab report, whatever
}
```

| Function | Who | What |
| --- | --- | --- |
| `register(name, origin, docHash)` | any resident | Creates the record, caller becomes holder |
| `transferCustody(id, to, note)` | the current holder | Hands it on, with a public note |
| `get(id)` | anyone | The current record |
| `count()` | anyone | How many products exist |

Only the current holder can transfer, enforced by `NotTheHolder(holder)` — a custom error
that tells you *who* the holder actually is, which is far more useful when debugging than a
bare revert.

Transferring to yourself reverts with `SameHolder()`. Small, but it stops a holder padding
the custody chain to look busier.

**The history lives in events**, not storage:

```solidity
event CustodyTransferred(uint256 indexed id, address indexed from, address indexed to, string note);
```

Storage keeps only the *current* holder; the full history is reconstructed from logs. This
is a deliberate and very common trade: events cost roughly an order of magnitude less gas
than storage, and anything a contract does not need to *read* should be an event.

The consequence is that history is only available to something that can query logs — which
is why module 2 of the labs has you build exactly that, and why real dApps run indexers.

## The detail that matters

`register` takes a `docHash` and a free-text `origin`. **The contract checks neither.**

Nothing stops someone registering "Highland Spring Water, origin: Highland Spring" for a
bottle filled from a tap. The chain will faithfully record that claim, timestamp it, and
preserve it for ever — which makes the lie permanent and attributable, but does not make it
false on chain.

So what has actually been gained?

- The claim is **attributable**: a specific address made it.
- It is **timestamped**: it cannot be backdated.
- It is **immutable**: it cannot be quietly revised when questions are asked.
- The custody chain is **complete**: no step can be hidden.

That is genuinely useful in a dispute. It is not the same as knowing what is in the jar,
and any supply-chain pitch that blurs the two is selling something.

The honest framing: a blockchain moves the trust problem from *many parties who can each
rewrite their own records* to *many parties who must each sign their claims in public*. It
does not remove it.

## Walk through it

1. Register a product in the Market.
2. Transfer custody to a classmate with a note.
3. Have them transfer it back.
4. On the explorer, filter the contract's logs for `CustodyTransferred` with your product
   id. That is the provenance.
5. Try to transfer a product you do not hold. `NotTheHolder` tells you who does.
6. Register a product with an obviously false origin. Nothing stops you. Sit with that.

## What actually happened on chain

```
ProductRegistered(id: 7, creator: 0x…, name: "Jar of honey", origin: "Miller Farm", docHash: 0x…)
CustodyTransferred(id: 7, from: 0x…, to: 0x…, note: "sold at market")
```

`id` is `indexed`, so a client can ask for exactly this product's history without
downloading every log the contract ever emitted. Choosing which parameters to index is a
design decision: up to three per event, each one a filter someone can use later.

## When a plain database is better

Within one company, always. A single manufacturer tracking its own inventory does not need
consensus with itself, and a database is faster, private and correctable.

The case appears when **several parties who do not fully trust each other** need one shared
record: a farm, a shipper, a processor, a retailer, a regulator. Nobody wants to host the
database everyone else depends on, and nobody wants to trust someone else's.

Even then, ask the hard question first: is a shared database with signed entries and an
audit log sufficient? It usually is, it is far cheaper, and "blockchain" is often the answer
to a governance problem that a contract cannot actually solve.

## What this does not fix

- **The input.** Someone typed the origin. A camera, a scale, a lab test — none of those
  are on chain either.
- **The physical link.** A QR code on a jar can be photographed and printed onto another
  jar. Tying atoms to bytes needs tamper-evident hardware, and that is its own field.
- **Collusion.** If every party in the chain agrees to lie, the record is consistent and
  wrong.

## Common mistakes

- **Storing history in an array.** Feels natural, costs a fortune, and grows unbounded.
  Events exist for this.
- **Unbounded strings.** A 10 KB `origin` costs real money and someone will try it.
- **Believing the record.** The most common error, and it is conceptual rather than
  technical.

## Security checklist

- [ ] Can anyone but the holder transfer custody?
- [ ] Can a product be transferred to the zero address, stranding it?
- [ ] Is the history complete from events alone, or does it depend on storage that changed?
- [ ] What stops an address registering ten thousand products?
- [ ] If the same `docHash` is registered twice, what does that mean? Should it be allowed?

## Extend it

1. Require a *receiving* signature — custody transfers only when the recipient accepts.
   Two transactions instead of one; say what that prevents.
2. Add batch and sub-batch relationships (a pallet holds cases, a case holds jars), and
   discover why GS1's EPCIS standard has aggregation events.
3. Restrict transfers to registered residents, and argue about whether that helps or just
   moves the problem.

## Further reading

- [GS1 EPCIS 2.0](https://www.gs1.org/standards/epcis) — the industry event model for
  exactly this, worth seeing before you invent your own schema.
- [Solidity events and logs](https://docs.soliditylang.org/en/latest/contracts.html#events)

**Next:** [Module 5 · Escrow →](05-escrow.md)
