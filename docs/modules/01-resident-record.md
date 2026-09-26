# Module 1 · The resident record

| | |
| --- | --- |
| **Contract** | `ResidentRegistry.sol` |
| **Stop** | Town Hall |
| **Standard** | None — plain Solidity with role-based access control |
| **Stamp** | Module 1 |

## The problem

Trustville needs to know who lives there. Every later module depends on it: only residents
can register products, issue certificates, harvest grain or claim the welcome grant.

The obvious approach is a list of names and addresses. It is also the wrong one, and
understanding *why* is most of this module. A public blockchain is readable by everyone,
for ever. Anything written to it is published — not "shared with the university", not
"available on request", but published, permanently, to anyone who ever looks.

So the design question is not "how do we store residents" but **how little can we store and
still have the record be useful?**

## The idea

Store a **hash** of the credential document, never the document.

The student keeps their own file — a letter, an enrolment record, whatever the town
accepts. The chain keeps a 32-byte fingerprint of it. Later, anyone holding the file can
prove it is the one that was registered, by hashing it and comparing. Anyone *without* the
file learns nothing at all.

```solidity
function register(bytes32 credentialHash) external {
    // ... stores the hash, the time, and who registered it
}
```

## Key terms

**Hash function.** A one-way function turning any input into a fixed-size output. Trustville
uses `keccak256`, the one the EVM provides natively. Three properties matter:

- *Deterministic* — the same input always gives the same output, so verification works.
- *One-way* — you cannot get the input back from the output, so publishing it is safe.
- *Avalanche* — changing one character changes roughly half the output bits, so "close" is
  meaningless. A document either matches or it does not.

**Commitment.** Publishing a hash is committing to a value without revealing it. You cannot
change your mind later, because any other document produces a different hash. This one idea
reappears in module 6 (sealed bids), module 7 (certificates) and module 13 (evidence).

**Role.** A named permission. `REGISTRAR_ROLE` may register on someone's behalf and revoke;
`DEFAULT_ADMIN_ROLE` may grant roles. Roles belong to *addresses*, and an address can be a
contract — which is how module 3 prevents any human from minting money.

## How it works

```solidity
struct Resident {
    uint64 since;          // 0 = never registered
    uint64 revokedAt;      // 0 = active
    bytes32 credentialHash;
}
```

Three fields. No name, no email, no student number.

| Function | Who | What it does |
| --- | --- | --- |
| `register(credentialHash)` | anyone, while open | Registers the caller |
| `registerFor(resident, hash)` | `REGISTRAR_ROLE` | Registers somebody else — for a student who cannot transact yet |
| `revoke(resident)` | `REGISTRAR_ROLE` | Marks them revoked; the record stays |
| `setOpenRegistration(bool)` | admin | Open registration on or off |
| `isResident(who)` | anyone | The question every other contract asks |

**Revocation does not delete.** `revokedAt` is a timestamp, and the original registration
stays visible. A chain has no delete — `SELFDESTRUCT` is gone, and even overwriting storage
leaves the history in every archive node. Designing as though deletion exists produces
systems that quietly lie about their own guarantees.

**Open registration is a policy switch.** `setOpenRegistration(false)` and only a registrar
may add residents. For a course you want it open; for a town you probably do not.

## The detail that matters

`register` takes a hash, so **the contract cannot check what it is a hash of**. Registering
`keccak256("")` or a hash of someone else's document both succeed.

That is not a flaw to fix in Solidity; it is the boundary of what the chain can know. The
contract enforces *structure* — one registration per address, only a registrar may revoke.
It cannot enforce *truth*. Truth needs somebody outside who checks documents, which is what
`REGISTRAR_ROLE` represents.

Being able to say exactly where the guarantee stops is the skill this module is teaching.

## Walk through it

1. Open Town Hall on the site and register.
2. Find the transaction on the explorer, and in it the `ResidentRegistered` event.
3. Read the `credentialHash` in the event data. This is public; everyone can see it.
4. Change one character of your credential text and hash it again — locally, no transaction.
   Compare. They share nothing.
5. Try to register a second time from the same address. It reverts with `AlreadyRegistered`.

## What actually happened on chain

```
ResidentRegistered(resident: 0x…, credentialHash: 0x…, registeredBy: 0x…)
```

Storage now holds `since = <block timestamp>`, `revokedAt = 0`, and your hash. Roughly
65,000 gas — three storage slots written from zero, which is the most expensive thing the
EVM does routinely. It is worth noticing now, because it is why later modules store hashes
and counters rather than strings.

## When a plain database is better

Almost always, for this alone. A registry run by one university, used only by that
university, gains nothing from being on a chain: the university could simply keep a table,
and everyone already trusts it about its own students.

The case for a chain appears when **the checker does not trust the keeper**. An employer in
another country, five years after you graduated, verifying that the record existed on a
date and has not been edited since — without asking the university and without the
university being able to quietly change it.

Be precise about that gap in your own designs, and honest when it is not there.

## What this does not fix

- The chain does not know you are a real student. Someone decided that off-chain.
- An address is not an identity. It is a public key, and people share, sell and lose them.
- Correlation is a real risk: everything your address ever does is linked. Your registration
  plus your transaction history plus anything you post can identify you even though your
  name is nowhere on chain.

That last point is worth sitting with. "No names on chain" is necessary, not sufficient.

## Common mistakes

- **Storing the document to be helpful.** Once, and it is public for ever.
- **Assuming revocation removes it.** It flags it.
- **Hashing inconsistently.** The UI hashes a specific string; verification must hash the
  same one or honest documents fail. Trailing newlines are the usual culprit.
- **Treating `isResident` as identity.** It says this address registered, nothing more.

## Security checklist

- [ ] Can somebody register on another person's behalf without the registrar role?
- [ ] Can a revoked resident re-register and clear their history?
- [ ] What happens if someone registers a hash of a document they do not hold?
- [ ] Does anything in the registry reveal a person's identity on its own? With the rest of
      the chain? Combined with a public class list?

## Extend it

1. Add credential *expiry*, so a record goes stale rather than being revoked by hand. Then
   decide what other contracts should do about an expired resident — and notice that this
   is a policy question hiding in a technical one.
2. Let a resident update their credential hash, keeping the old one in history. What have
   you just made possible, and what have you made harder to audit?
3. Replace `REGISTRAR_ROLE` with a two-of-three multisig (module 11). Say what that costs
   in convenience and what it buys.

## Further reading

- [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/5.x/access-control)
- [keccak256 and the Ethereum EVM](https://ethereum.org/en/developers/docs/evm/opcodes/)
- W3C Verifiable Credentials — the standards-track version of "issuer signs, holder keeps,
  verifier checks", which module 7 follows more closely.

**Next:** [Module 2 · The soulbound Passport →](02-soulbound-passport.md)
