# Modules 7–8 · Verifiable certificates, Event tickets

## The problem

A diploma is a PDF, and anyone can edit a PDF. Checking one means emailing the college and
hoping somebody answers — and if the college closes, the record may be gone. Event tickets
have the mirror problem: they are easy to forge, easy to sell twice, and the organiser takes
the money for an event that might never happen.

## Why a blockchain

| Need | Blockchain answer | When a database is better |
| --- | --- | --- |
| Check a document without contacting the issuer | Hash anchored on chain; anyone can compare | The verifier already trusts and can call the issuer |
| A record that outlives the institution | Public chain state, no server to keep running | An institution certain to be around and reachable |
| A ticket that cannot be copied or reused | Token balance; redeeming burns it | Scanned barcodes with a central database at the door |
| Money returned if the event is cancelled | Contract holds funds until the event starts | An escrow provider both sides trust |

## Design

```
CertificateRegistry  issue(holder, course, docHash) → id; revoke(id, reason)
                     verifyDocument(docHash) → known, valid, issuer, holder, course
EventTickets         ERC-1155: one token id per event, N identical tickets inside
                     createEvent → buy → redeem (burns) | cancel → refund | withdrawProceeds
```

**Only the hash goes on chain.** The certificate document stays with the holder. Change one
character and the hash no longer matches, so the chain can prove a document is *the* document
without ever publishing it. It also means the chain reveals nothing about a student who
never shows their certificate to anyone.

**Anyone may issue, and that is the point.** The registry does not decide who is a real
college — it records who signed what. A verifier must always ask *who issued this*, not just
"is it on the chain?". Students who skip that step will happily accept a certificate someone
issued to themselves from a second wallet. Have them try it.

**Revocation never deletes.** A revoked certificate keeps its record and gains a date, so a
verifier can still answer "was this valid last March?". Deleting history would break exactly
the questions the registry exists to answer.

**Why ERC-1155 for tickets.** One token id per event, many identical tickets inside it.
ERC-721 would mean a separate token per seat and a separate transaction per sale; ERC-20
could not tell one event from another. Redeeming burns the ticket, so it cannot be used
twice or resold after entry — while an unredeemed ticket stays transferable, which is how a
legitimate resale works.

**Money is held until the event starts.** The same escrow idea as module 5: the organiser
withdraws only once the event has begun, and a cancelled event lets every buyer refund and
burn their tickets. The pattern recurs wherever one side pays before the other delivers.

## Try it

1. **Issue a certificate** to a classmate. Paste the same text into the verify box: valid.
   Add one character and try again: unknown. That one byte is the whole mechanism.
2. **Revoke it** from the issuing account and verify again — it now reads REVOKED, and the
   record is still there.
3. **Issue yourself a certificate from a second wallet** claiming a degree you do not have.
   It verifies as valid. Ask what that proves, and what it does not.
4. **Create an event** with a price, buy a ticket from another account, and check the token
   balance of the tickets contract on the explorer — the money is there, not with the organiser.
5. **Redeem** and watch the balance burn to zero; try redeeming again.
6. **Cancel an event** that has sold tickets and refund yourself.

## Extend it

1. Add an issuer allow-list so only approved institutions can issue, and argue about who
   controls the list.
2. Add certificate expiry, so a first-aid certificate lapses after two years without revocation.
3. Add a resale cap that prevents transferring a ticket for more than its face value — then
   work out how someone could get around it.

## Security checklist

- [ ] Can anyone but the issuer revoke, or un-revoke?
- [ ] What happens if the same document is issued twice? Should that be allowed?
- [ ] Can the organiser withdraw before the event, or after cancelling?
- [ ] Can a buyer refund twice, or refund after redeeming?
- [ ] Does any function transfer tokens before writing state?
- [ ] Does anything on chain reveal a person's name, grade or student number?
