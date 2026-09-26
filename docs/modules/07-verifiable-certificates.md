# Module 7 · Verifiable certificates

| | |
| --- | --- |
| **Contract** | `CertificateRegistry.sol` |
| **Stop** | College |
| **Model** | W3C Verifiable Credentials, simplified — hash anchoring |
| **Stamp** | Module 7 (awarded to the **issuer**) |

## The problem

You have a degree certificate. An employer in another country wants to know it is real.

Today they email the university, wait, and hope someone answers — or they trust a PDF,
which anyone can edit. Diploma fraud is a real industry, and the usual fix is to centralise
verification with a company who charges for each check and becomes a new single point of
failure.

## The idea

**The issuer signs, the holder keeps, the verifier checks.**

The university issues a certificate and anchors its **hash** on chain, along with who
issued it, to whom, and when. The student keeps the document. Anyone holding the document
can hash it and compare — no phone call, no fee, no permission.

The document itself never touches the chain. That is not an optimisation; a transcript is
personal data and a public ledger is the worst possible place for it.

## Key terms

**Verifiable credential.** A claim made by an issuer about a subject, which a verifier can
check without contacting the issuer. The W3C model has three roles — issuer, holder,
verifier — and this module is a deliberately simplified version of it.

**Anchoring.** Putting a hash on chain so that a document's existence at a point in time
can be proven later. The chain becomes a timestamping and integrity service, nothing more.

**Revocation.** Cancelling a credential after issuance. This is the genuinely hard part of
every credential system, on chain or off, and the reason most academic designs quietly skip
it.

**Selective disclosure.** Proving one fact from a credential ("I have a degree") without
revealing the rest ("in this subject, with these marks, from this year"). Not solved here —
it needs module 16's machinery.

## How it works

```solidity
struct Certificate {
    address issuer;
    address holder;
    uint64 issuedAt;
    uint64 revokedAt;   // 0 = valid
    string course;
    bytes32 docHash;
}

mapping(bytes32 => uint256) public idOfDocument;   // hash → id
```

| Function | Who | What |
| --- | --- | --- |
| `issue(holder, course, docHash)` | any resident | Anchors the certificate |
| `revoke(id, reason)` | the issuer only | Marks it revoked, publicly, with a reason |
| `verifyDocument(docHash)` | anyone | "Is this document anchored, and is it valid?" |
| `isValid(id)` | anyone | Exists and not revoked |

The `idOfDocument` mapping is what makes verification one call: a verifier does not need to
know the certificate id, only to possess the file. Hash it, look it up, done.

The contract refuses `SelfIssue()` — you cannot issue a certificate to yourself — and
`DocumentAlreadyRegistered(id)`, so the same document cannot be anchored twice.

## The detail that matters

**Revocation cannot delete.**

```solidity
c.revokedAt = uint64(block.timestamp);
emit CertificateRevoked(id, msg.sender, reason);
```

The certificate stays. It is marked, with a timestamp and a public reason, and that is the
strongest thing a chain can do.

This cuts both ways, and the tension is worth teaching rather than glossing:

- **It protects the holder.** An issuer cannot quietly erase a certificate and claim it was
  never granted. The original issuance is permanent evidence.
- **It exposes the holder.** "Revoked: academic misconduct" is visible for ever, to
  everyone, with no appeal and no expiry. A university database can correct a mistake. A
  chain records the correction as another permanent entry.

Real credential systems handle this with status lists and expiry rather than permanent
public flags, precisely because a permanent public accusation is a serious thing to build.

**Anyone can issue.** The contract checks the issuer is a resident, nothing more. Register
an address, and you can issue "PhD in Astrophysics" to anyone.

That is correct behaviour, and it is the thing students must understand: the chain proves
*who* issued a certificate and *that it has not changed*. It has no opinion on whether the
issuer is credible. Credibility comes from outside — the verifier must recognise the
issuer's address, exactly as they must recognise a university's letterhead today.

The chain solved integrity and timestamping. It did not solve authority, and no chain does.

## Walk through it

1. Write a short text file. This stands in for a transcript.
2. Issue a certificate to a classmate with the file's hash.
3. **Classmate:** verify it — hash the file, look it up, confirm issuer and validity.
4. Change one character in the file. Hash again. Verify. It is not found.
5. Revoke the certificate with a reason.
6. Verify once more: the certificate is still there, now marked revoked.
7. Try to revoke someone else's certificate. `NotTheIssuer(issuer)`.

## What actually happened on chain

```
CertificateIssued(id: 4, issuer: 0x…, holder: 0x…, course: "CS 5590", docHash: 0x…)
Stamped(tokenId: …, moduleId: 7, by: certificateRegistry)
...
CertificateRevoked(id: 4, issuer: 0x…, reason: "issued in error")
```

Three of the four issue parameters are `indexed`, so a verifier can filter by issuer or by
holder without scanning every log. `course` is not indexed — indexed strings are stored as
hashes and become unreadable, which is a real trap: index what you filter by, leave
readable what you display.

## When a plain database is better

Inside one institution, always. The registry has the data, controls the process, and can
correct mistakes — all properties a chain removes.

Anchoring earns its place when **the verifier does not trust the issuer's database**: cross
border, years later, after a merger or a closure, or when the issuer has an incentive to
revise history. Note that the chain does not have to be the only record — anchoring
alongside a normal database gives you integrity proof without giving up the database's
advantages, and that hybrid is what most serious deployments actually do.

## What this does not fix

- **Issuer authority.** Anyone can issue anything. Recognising legitimate issuers is
  off-chain work.
- **Privacy of the fact.** The course name is on chain in clear text. "CS 5590, revoked" is
  public even though the transcript is not.
- **Selective disclosure.** Showing a certificate shows the whole thing, and links it to an
  address with a full transaction history.
- **Lost documents.** Lose the file and you cannot prove anything. The chain has the hash,
  not the content.

## Common mistakes

- **Putting the document on chain.** Irreversible, public, and usually illegal for personal
  data.
- **Hashing inconsistently.** Text encoding, line endings, trailing whitespace. Pick the
  raw bytes and document it.
- **Indexing the course string**, then wondering why the explorer shows a hash.
- **Overclaiming in the UI.** "✓ Verified" invites the reader to believe the issuer is
  legitimate. "Issued by 0x… on 3 March, not revoked" is the honest version.
- **No revocation at all.** Very common in student projects, and it makes the system
  unusable in practice.

## Security checklist

- [ ] Can anyone but the issuer revoke?
- [ ] Can a revoked certificate be un-revoked?
- [ ] Can the same document be anchored twice, by different issuers?
- [ ] What does the on-chain record leak about the holder?
- [ ] If the issuer's key is stolen, what can the thief do — and how would anyone know?
- [ ] Can a verifier distinguish a real issuer from a lookalike address?

## Extend it

1. Add expiry, so a certificate lapses rather than needing revocation. Then decide what
   `isValid` should say about an expired one.
2. Implement a **status list**: one bitmap covering thousands of certificates, so revocation
   costs one bit instead of one transaction. This is what the W3C standard actually does —
   work out why.
3. Add an issuer allowlist controlled by the DAO from module 12, and argue about who should
   be on it.

## Further reading

- [W3C Verifiable Credentials Data Model](https://www.w3.org/TR/vc-data-model-2.0/)
- [Bitstring Status List](https://www.w3.org/TR/vc-bitstring-status-list/) — revocation at
  scale.
- SD-JWT VC, for selective disclosure without zero-knowledge proofs.

**Next:** [Module 8 · Event tickets →](08-event-tickets.md)
