# Lab 3 · Writing transactions

**Deliverable:** a pull request: certificate issuing and verification, done properly ·
**Time:** two hours

Reading a chain is easy. Writing to one is where dApps are actually judged, because a
transaction can fail in a dozen ways and most of them happen after the user has committed.
This lab is about the whole lifecycle, and about being honest with the person waiting.

## The job

Rebuild the College's certificate flow so that issuing and verifying a certificate is
something a non-technical user could complete without help.

**Issuing.** The issuer picks a file from their computer, names the course, and issues to a
holder's address. The file is hashed **in the browser** — it never leaves the machine.

**Verifying.** Anyone pastes or drops a file and gets a verdict: is this the document
behind certificate #N, is the certificate still valid, and who issued it.

**Revoking.** The issuer can revoke with a reason, and the interface makes the consequence
clear before they confirm: the certificate is not deleted, it is permanently marked.

## Acceptance criteria

- [ ] File hashing happens client-side; files are never uploaded anywhere.
- [ ] A 50 MB file does not freeze the tab.
- [ ] Before sending, the transaction is **simulated**; a failure that simulation catches
      never reaches the wallet.
- [ ] Every state is visible and distinct: idle, simulating, waiting for the wallet,
      pending on chain, confirmed, failed.
- [ ] A user rejecting in MetaMask returns to idle with no scary error — it is not an
      error, it is a decision.
- [ ] A revert shows the **decoded custom error** as a sentence. `0x82b42900` is not an
      error message.
- [ ] Verification tells the difference between three cases: wrong document, right document
      but revoked certificate, and no such certificate.
- [ ] The revoke control requires confirmation and states that revocation is permanent.
- [ ] CI green.

## Technical requirements

**Simulate first.** `publicClient.simulateContract` before `writeContract`. It costs one
RPC call and catches most reverts before the user signs. This is the single habit that most
separates a professional dApp from a student one.

**Decode errors.** The contracts use custom errors: `NotTheIssuer()`, `AlreadyRevoked()`,
`NotAResident()`. Map them to sentences. `app/src/tx.js` already does some of this — extend
it rather than writing a second version.

**Hash large files without blocking.** Read as an ArrayBuffer and hash the bytes. If the UI
freezes on a big file, you are doing it on the main thread in one go.

**Idempotence.** Double-clicking the issue button must not send two transactions. Disable
it, and say in your PR what would happen on chain if you had not.

## The interesting question

A certificate hash proves a document has not changed since it was issued. It does **not**
prove the issuer was entitled to issue it, and it does not stop them issuing the same
certificate to fifty people.

In your PR, answer in a short paragraph: **what does your verification screen actually
tell a sceptical employer, and what does it not?** Then make sure the interface does not
overclaim. Wording like "✓ Verified" invites a reader to believe more than you have
proven.

## Common ways this goes wrong

- **Hashing the filename or a data URL** instead of the file bytes. Works consistently for
  the person who wrote it and for nobody else.
- **Hashing text instead of bytes.** A `.docx` read as text hashes differently every time
  on some platforms. Pick bytes and be consistent.
- **Treating rejection as failure.** The most common wallet outcome is "user changed their
  mind". Red error toasts for that are a tell.
- **A spinner with no timeout.** If the transaction never confirms, what does the user see
  in two minutes? Decide.
- **Optimistic UI that lies.** Showing the certificate as issued before it is mined, with
  no rollback when it reverts, is worse than being slow.

## Out of scope

No contract changes — `CertificateRegistry` stays as it is. No file storage: the document
stays on the user's machine, which is the design.

## Hand in

1. The PR, CI green, reviewed and approved.
2. Your review of someone else's PR. Specifically: reject in MetaMask, and try to issue a
   certificate you are not entitled to issue. Report what you saw.
3. An incident write-up if anything broke.
