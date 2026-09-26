# Module 9 · Property deeds

| | |
| --- | --- |
| **Contract** | `PropertyDeeds.sol` |
| **Stop** | Housing |
| **Standard** | ERC-721, plus a certification flag |
| **Stamp** | Module 9 |

## The problem

Land registration is one of the oldest uses of writing, and it is still hard. Who owns this
house? The answer lives in a government register, and in much of the world that register is
incomplete, contested, slow to search, or corruptible. Title fraud — forging a transfer of
someone else's property — is a real crime with real victims.

"Put land titles on a blockchain" is therefore one of the most frequently proposed
applications, and one of the most frequently misunderstood. This module builds it *and*
shows you exactly where it breaks.

## The idea

A deed is an NFT. Transferring the token transfers the record of ownership, and the history
of transfers is public and append-only.

Then one extra idea that makes the module honest: **certification**. The town can vouch
that a particular owner really holds a particular property — and that vouching is
automatically thrown away the moment the token moves.

## Key terms

**Deed.** A document evidencing ownership of land. Note "evidencing": the deed is not the
land, and this distinction is the whole module.

**Certification.** A statement by an authority that a record matches reality. Here it is a
single boolean set by `CERTIFIER_ROLE`.

**The registry gap.** The difference between what a register says and what the law
recognises. On chain, this is the gap between the token holder and the legal owner.

**Transfer hook.** Code that runs on every token movement. In OpenZeppelin v5 this is
`_update`, and overriding it is how a token adds behaviour to transfers.

## How it works

```solidity
struct Property {
    address registrant;
    uint64 registeredAt;
    bool certified;
    string addressLine;
    bytes32 docHash;   // hash of the off-chain title document
}
```

| Function | Who | What |
| --- | --- | --- |
| `register(addressLine, docHash)` | any resident | Mints the deed to the caller |
| `certify(id)` | `CERTIFIER_ROLE` | The town vouches for this owner |
| `transferFrom` / `safeTransferFrom` | the owner | Standard ERC-721 |
| `get(id)` | anyone | The record |
| `tokenURI(id)` | anyone | On-chain JSON, including certification |

Anyone registered as a resident can register any property, with any address line. The
contract does not know what land exists.

## The detail that matters

**Certification does not survive a transfer:**

```solidity
function _update(address to, uint256 id, address auth) internal override returns (address) {
    address from = super._update(to, id, auth);
    if (from != address(0) && to != address(0) && _props[id].certified) {
        _props[id].certified = false;
        emit CertificationCleared(id, from);
    }
    return from;
}
```

Read what this says. The town certified that **Alice** owns 14 Mill Lane. Alice sells the
token to Bob. The chain now records Bob as holder — but the town never said anything about
Bob, so the certification is cleared and an event announces it.

This is the module's central lesson, and it is worth stating twice: **the chain can move the
token perfectly and still be wrong about the world.** A token transfer is not a conveyance.
It has no searches, no mortgage discharge, no signatures witnessed, no stamp duty, no
recourse if the seller had no right to sell. The certification flag is the town admitting
that only an off-chain process can connect the two, and clearing the flag is the contract
refusing to pretend otherwise.

Compare with module 2's Passport, which cannot move at all, and module 8's tickets, which
move freely and carry everything with them. Deeds are the interesting middle: the token
moves, but a piece of its meaning does not.

**The zero-address conditions matter.** Minting (`from == 0`) must not clear a flag that was
never set, and burning (`to == 0`) need not bother. Getting these guards wrong is a common
source of subtle bugs in transfer hooks.

**`docHash` again.** As in module 7, the document stays off chain and only its hash is
anchored. A title deed is full of names and addresses; publishing it would be a data
protection incident, not a feature.

## Walk through it

1. Register a property. You hold the deed.
2. Look at `tokenURI` on the explorer. Certified: no.
3. Ask the instructor (who holds `CERTIFIER_ROLE`) to certify it. Look again: yes.
4. Transfer the deed to a classmate.
5. Look a third time. Certified: no — and there is a `CertificationCleared` event saying so.
6. Register "Buckingham Palace" as a property. Nothing stops you. Note that the chain will
   keep that claim, with your address on it, for ever.

## What actually happened on chain

```
Transfer(from: 0x0, to: registrant, tokenId: 3)         // ERC-721 mint
PropertyRegistered(id: 3, registrant: 0x…, addressLine: "14 Mill Lane", docHash: 0x…)
Stamped(tokenId: …, moduleId: 9, by: propertyDeeds)
...
PropertyCertified(id: 3, by: certifier, owner: 0x…)
...
Transfer(from: owner, to: buyer, tokenId: 3)
CertificationCleared(id: 3, previousOwner: 0x…)
```

The `Transfer` and `CertificationCleared` events are emitted by the same transaction, in
that order, because the hook runs inside the transfer. Reading them in order is how an
indexer keeps its view of certification correct.

## When a plain database is better

For an actual land registry, a database — essentially always, today. A registry needs to
correct errors, enforce court orders, handle inheritance and incapacity, redact personal
data, and answer to a legal system. Every one of those is something a public immutable
ledger is bad at.

The honest cases where a chain adds something:

- **Fractional or tokenised property interests** that trade often, where the token *is* the
  asset rather than evidence of one.
- **Registries in jurisdictions where the state register is the threat** — though note that
  a chain does not stop a government from simply not recognising it.
- **Audit trails alongside** a conventional register, anchoring its state so that silent
  revision becomes detectable.

Several countries have piloted land registries on chains. The pattern in the results is
consistent: the technology worked and the institutional problem remained.

## What this does not fix

- **Legal ownership.** A court decides that, and it has never heard of your token.
- **Lost keys.** Lose the key and you lose the deed, with no registrar to appeal to. For a
  house, this is a serious objection rather than an inconvenience.
- **Duplicate registrations.** Two people can register the same address. The contract cannot
  tell.
- **Theft by signature.** If someone gets your key, the fraudulent transfer is final and
  looks exactly like a legitimate one.
- **What the property is.** A string. Not a survey, not coordinates, not a boundary.

## Common mistakes

- **Treating the token as the title.** The single biggest conceptual error in this space.
- **Letting certification travel with the token.** Then a certified deed can be sold to
  anyone and the certification means nothing.
- **Forgetting the mint and burn cases in the hook.** `from == 0` and `to == 0` need
  handling.
- **Putting the deed document on chain.** Personal data, permanently public.
- **No way to correct an error.** Real registries need rectification. Decide deliberately
  whether yours has it, and who can use it.

## Security checklist

- [ ] Can a non-certifier certify? Can a certifier un-certify at will?
- [ ] Does certification survive a transfer? A transfer back?
- [ ] Can the same address line be registered twice?
- [ ] Can a deed be burned, and what happens to a lease that depends on it (module 10)?
- [ ] Who can `approve` a transfer, and does that bypass any of your checks?
- [ ] If a key is lost, is there any recovery path at all — and should there be?

## Extend it

1. Add a rectification function for the registrar, then write down exactly who may call it
   and what stops it being a back door. You have just rediscovered why land registries have
   procedure.
2. Require certification before a deed may be transferred, and see what that does to the
   market — and to the registrar's power.
3. Add a mortgage lien: a second party who must consent to a transfer. Model it as a flag,
   then as an approval, then argue about which is right.

## Further reading

- [ERC-721](https://eips.ethereum.org/EIPS/eip-721)
- [OpenZeppelin ERC721 `_update`](https://docs.openzeppelin.com/contracts/5.x/api/token/erc721#ERC721-_update-address-uint256-address-)
- Search for published evaluations of blockchain land registry pilots, and read the
  conclusions rather than the announcements.

**Next:** [Module 10 · Rent escrow →](10-rent-escrow.md)
