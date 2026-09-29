# Module 16 · Zero-knowledge selective disclosure

| | |
| --- | --- |
| **Contracts** | `PrivacyLab.sol`, `PoseidonT3.sol` (generated), `Groth16Verifier.sol` (generated) |
| **Circuit** | `circuits/membership.circom`, `circuits/merkle.circom` |
| **Stop** | Privacy Lab |
| **Patterns** | Groth16 zk-SNARK; Merkle membership proof; commitment + nullifier; signal binding |
| **Stamp** | Module 16 (on **enrolment**, not on posting — and the reason why is the module) |

> This is the only module where the thing being taught is mostly **what the guarantee does
> not cover**. The cryptography works. It will not save you from a small crowd, a
> distinctive writing style, or paying your own gas.

## The problem

Module 7 gave Trustville verifiable certificates, and ended by admitting what it could not
do.

To prove you hold one, you show it. Showing it reveals the course, the issuer, the date,
the document hash — and, worse, it ties all of that to an address whose every transaction
is public forever. A student who wants to say *"someone with a certificate from this
college thinks the lifts have been broken for a month"* has two options today: say it with
their name on it, or say it with no evidence at all.

Those are not the only two options, and the gap between them is where a great deal of real
life happens. Whistleblowing. Peer review. Voting. Proving you are over eighteen without
handing over your date of birth, your address, and a photograph. Every one of those is the
same shape: **prove one predicate, reveal nothing else.**

Trustville could not do it. Now it can.

## The idea

Split the claim in two, and put time between the halves.

**Enrol, in public.** Holding a valid certificate, you invent a secret `s` and publish
`commitment = Poseidon(s)`. That transaction is signed by you and everyone can see it.
That is fine — it is the step that proves you are *entitled* to be in the set, and it is
supposed to be seen. Your commitment becomes a leaf in a Merkle tree the contract
maintains.

**Prove, later, from anywhere.** From any address at all — a fresh one with no history —
you submit a zero-knowledge proof of this statement:

> I know a secret whose Poseidon hash is a leaf somewhere under the root `R`, my nullifier
> for topic `t` is `N`, and the message I am attaching is exactly this one.

The contract checks the proof and learns that **someone in the set** is speaking. It
cannot learn which one. Neither can you, reading the chain afterwards, and neither can the
validators, and neither can we.

The leap worth pausing on: the contract verifies a statement about a secret **it never
receives**. Not encrypted, not hashed for later, not held in escrow — never transmitted.
That is the part that sounds impossible the first time and stays slightly astonishing
afterwards.

## Key terms

**Zero-knowledge proof.** A proof that a statement is true which reveals nothing beyond
its truth. Three properties: *completeness* (true statements can be proved), *soundness*
(false ones cannot), *zero-knowledge* (the proof leaks nothing else).

**zk-SNARK.** Succinct Non-interactive ARgument of Knowledge. Succinct: the proof is a few
hundred bytes and verifying is fast, no matter how big the computation was.
Non-interactive: one message, no back-and-forth, so it fits in a transaction.

**Groth16.** The SNARK used here. The smallest proofs and cheapest verification in common
use — and the reason we chose it — at the cost of a **per-circuit trusted setup**. Change
one line of the circuit and the whole setup must be redone.

**Circuit.** The computation, written as arithmetic constraints over a finite field.
Written in Circom here. Not a program that runs: a set of equations that must hold.

**Constraint.** One equation. Our circuit has **4,342 non-linear constraints**, and that
number is the unit of cost in this world — it sets proving time, key size, and setup time.

**Witness.** Every value in the circuit for one particular run: the public inputs, and the
private ones you are hiding.

**Public / private signals.** Our circuit has 4 public (`root`, `nullifierHash`, `topic`,
`signalHash`) and 33 private (`secret`, and the 16 path elements with their 16 indices).
The public ones go on chain in the clear. **Anything public is revealed — decide that
list deliberately.**

**Commitment.** `Poseidon(secret)`. Binding (you cannot find a second secret with the same
hash) and hiding (the hash tells nobody the secret).

**Nullifier.** `Poseidon(secret, topic)`. Derived from the secret, so only you can produce
yours; unlinkable to your commitment, so it does not identify you; deterministic, so the
contract can refuse a second one. This is how you get *one post per member* without
knowing who the members are.

**Merkle proof.** The 16 sibling hashes that let anyone recompute the root from your leaf.
Proving membership of 65,536 people costs 16 hashes, not 65,536 comparisons.

**Anonymity set.** The group you are indistinguishable from. Here: everyone enrolled.
**This is your actual privacy, and the cryptography has nothing to do with it.**

**Trusted setup.** Randomness used to generate the proving and verifying keys, which must
then be destroyed. Whoever keeps it can forge proofs of false statements that verify
perfectly. Often called *toxic waste*, which is exactly the right name.

## How it works

### The circuit

`circuits/membership.circom`, in full, is short enough to read in one sitting. The shape:

```circom
component commitmentHasher = Poseidon(1);
commitmentHasher.inputs[0] <== secret;          // commitment = Poseidon(secret)

component nullifierHasher = Poseidon(2);
nullifierHasher.inputs[0] <== secret;
nullifierHasher.inputs[1] <== topic;
nullifierHasher.out === nullifierHash;          // and it is the one you claimed

component tree = MerkleTreeChecker(levels);
tree.leaf <== commitmentHasher.out;
tree.root <== root;                             // and it is under the root you claimed
```

Three claims, tied together by the single `secret` that appears in all of them. You cannot
satisfy one with one secret and another with a different one.

Then this, which looks like a mistake and is not:

```circom
signal signalSquare;
signalSquare <== signalHash * signalHash;
```

`signalHash` is a public input that nothing else constrains. An unused public input is
**silently optimised out of the circuit** — and a public input that is not in the circuit
is one the verifier does not actually check. The proof would verify against *any* message.
Squaring it forces it into a constraint, which forces it into the verifying key. One line,
and without it the entire signal-binding mechanism is decorative. This is the single most
commonly repeated bug in applied zero-knowledge, and it fails **open**.

### The tree, in three places

The same incremental Merkle tree is implemented three times:

| Where | File | Role |
| --- | --- | --- |
| The circuit | `circuits/merkle.circom` | proves the path is valid |
| The chain | `contracts/src/PrivacyLab.sol` | builds the tree as people enrol |
| The browser | `app/src/zk/tree.js` | rebuilds it to produce your path |

They must agree **exactly** — same hash, same empty-subtree constant, same depth, same
ordering. One mismatched value anywhere produces a proof that is mathematically perfect
and verifies against a root nobody has. The on-chain error for that is `UnknownRoot`, or,
if you are less lucky, `BadProof`. Neither points within a mile of the cause.

So the agreement is tested rather than hoped for:

- `test_TheZeroValueMatchesTheJavascript` asserts the contract's constant equals the
  JavaScript's.
- `test_PoseidonMatchesCircomlib` asserts the deployed hasher matches circomlib's published
  value for `Poseidon(1, 2)`.
- `PrivacyLabProof.t.sol` enrols the fixture's leaves into a real contract and asserts
  `lab.currentRoot() == root` **before** submitting the proof — so a disagreement fails
  with *"contract tree != tree.js tree"* rather than an opaque revert.

### Why Poseidon and not keccak256

Keccak inside a SNARK costs roughly **150,000 constraints**. Poseidon costs about **240**.
Same security claim, three orders of magnitude apart, because Poseidon is built from field
arithmetic — which is what the constraint system speaks natively — and keccak is built from
bit operations, which have to be simulated one bit at a time.

This is a genuine surprise the first time you meet it: *the hash function is chosen for the
proof system, not for the application.* It also explains `PoseidonT3.sol`, which is
circomlib's own compiled hasher deployed verbatim from embedded bytecode rather than a
Solidity port. A hand-written port that is subtly wrong is a bug you would find weeks
later, in production, with no error message to follow.

### The contract

`PrivacyLab.sol` does four things and refuses to do a fifth.

```solidity
if (!isKnownRoot(root)) revert UnknownRoot();
if (nullifierUsed[nullifierHash]) revert NullifierAlreadyUsed();
uint256 signalHash = hashSignal(text);
if (!verifier.verifyProof(pA, pB, pC, [root, nullifierHash, topic, signalHash])) {
    revert BadProof();
}
nullifierUsed[nullifierHash] = true;
emit AnonymousPost(topic, nullifierHash, text);
```

The fifth thing — recording who sent it — is the one it does not do. There is no `author`
field, no `msg.sender` in the event, nothing. `test_ThePostNamesNobody` asserts that,
because "we removed the author field" is the kind of claim that quietly stops being true
during a refactor.

Note `hashSignal` recomputes the signal from the text itself rather than trusting a value
the caller supplies. A caller-supplied `signalHash` would let anyone attach a proof to a
different message — the exact attack the squaring constraint exists to prevent, walked
straight back in through the front door.

### Root history

A proof is built against the root you saw. If someone enrols while you are proving, the
root moves and your proof is stale. `ROOT_HISTORY = 32` keeps the last thirty-two roots
valid, so a few minutes of enrolments do not invalidate work in progress.

The window is a real trade-off, not a free convenience: a longer one is friendlier and
gives an observer more information, because a proof against an old root says *"built when
the set was this small"*. Thirty-two is a guess. Defending a different number is a
reasonable exercise.

### Where the stamp goes

The passport stamp is written on **enrolment**, never on posting.

A stamp is written to your passport, and your passport is your address. Stamping at post
time would write "this address posted anonymously" into a public record — undoing, in one
line, the entire thing the module exists to provide. Enrolment is already public, so the
stamp costs nothing there.

That trap is worth staring at, because nothing about it is cryptographic. The proof system
is flawless and the feature leaks anyway, through a bit of unrelated bookkeeping that
seemed obviously harmless. Most real privacy failures look like this.

## The detail that matters

**The trusted setup, and which half of ours is real.**

Groth16 needs randomness to generate its keys, and that randomness must be destroyed.
Whoever keeps it can forge a proof of any statement — including false ones — and no
verifier, on chain or off, can tell the difference. The defence is a *ceremony*: many
independent parties each contribute, and the result is sound as long as **at least one**
discarded their contribution honestly.

The setup has two phases.

**Phase 1** is universal. It depends only on circuit *size*, so the whole ecosystem shares
one. `scripts/build-circuit.sh` downloads the **Perpetual Powers of Tau** — a real ceremony
with many independent contributors and a public transcript. Nothing we do here weakens it.
(If the download fails, the script falls back to generating phase 1 locally and says so
loudly. If that happened on your build, phase 1 is theatre too.)

**Phase 2** is per circuit, so it has to happen here. Ours contributes **once**, from one
machine, unattended, with entropy from `/dev/urandom`, into a file committed to a public
repository. Every participant is us.

So half our setup is genuinely trustworthy and half is a performance of one. For a teaching
chain with worthless tokens, the performance is fine. **Shipping it anywhere real would be
negligent.** Real deployments run multi-party ceremonies with dozens of contributors,
published transcripts and independent verification — Zcash, Semaphore and Tornado Cash all
did, and their write-ups are the interesting reading.

Notice, too, what a compromised setup does and does not break. Forged proofs become
possible: soundness is gone. But *zero-knowledge* survives — an attacker with the toxic
waste still cannot read anyone's secret. Knowing which property fails is the difference
between "we need to rebuild" and "everyone must rotate".

The practical consequence for you: `Groth16Verifier.sol` is bound to exactly one proving
key. Rebuild the circuit and the old verifier stops accepting new proofs, and the old
`.zkey` in the browser stops working against the new verifier. **The contract and
`app/public/zk/` have to ship as one change, always.** Mismatched halves produce `BadProof`
on every post, and `BadProof` will not tell you that is what happened.

## Walk through it

You need a valid certificate from module 7. Get one issued to you at the College first.

1. **Generate a secret** in the Privacy Lab. It appears once. Copy it somewhere you will
   still have next week. It is kept in this browser's local storage, which means clearing
   site data destroys it permanently — there is no reset, no recovery, and nobody who can
   help — and that anyone who can open your browser has it.
2. **Enrol**, choosing your certificate. Signed by you, in public. Watch the `Enrolled`
   event: it names your address, your certificate and your commitment, and that is
   deliberate.
3. **Read the member count** at the top of the panel before going further. If it says 1,
   stop and go find three classmates. A proof of membership in a set of one is a signed
   confession with extra steps.
4. **Write a notice and pick a topic.** Press *Build the proof*. Watch the status: loading
   the prover (~1.4 MB of JavaScript), rebuilding the tree, then proving. A few seconds on
   a laptop. All of it in your browser — open the network tab and confirm nothing leaves.
5. **Switch MetaMask to a different account** — one that has never enrolled, never held a
   certificate, and ideally has never done anything else here. The panel warns you if you
   skip this. Read the warning rather than clicking past it; it is the most important
   sentence on the page.
6. **Post anonymously.** The proof, the root, the nullifier, the topic and the text go on
   chain. No address does.
7. **Try to post again on the same topic.** `NullifierAlreadyUsed`. One member, one post
   per topic — enforced without the contract knowing who you are.
8. **Change one character of your message and post the old proof.** `BadProof`. The
   message is bound into the proof; nobody can lift one from the mempool and attach their
   own words.
9. **Now do the actual exercise.** Open the transaction on the explorer and try to work out
   who posted it. Write down everything you *can* determine. Then write down what you would
   need in order to finish the job. That list is the real content of this module.

## What actually happened on chain

**`Enrolled(certificateId, by, commitment, leafIndex)`** — fully public. Your address, your
certificate, your commitment, your position in the tree. This is the membership roll, and
it is meant to be readable.

**`AnonymousPost(topic, nullifierHash, text)`** — no author. The nullifier is indexed so
the contract can refuse a repeat; it is derived from your secret and your topic, and it is
not linkable to your commitment by anyone who does not know the secret.

**The transaction itself** still has a sender, who paid the gas, at a particular moment,
from a particular IP address, through a particular RPC endpoint. **The proof hides the
author. It does not hide the envelope.** Go and look at the sender on the explorer and see
what you can learn.

Read the receipt's gas figure too. Notice that verification is a fixed cost — the same
three pairing operations whether the tree holds four members or sixty-five thousand, and
whether the circuit had four thousand constraints or four million. That flatness is the
whole promise of "succinct", and it is why this is worth doing on a chain at all.

## When a plain database is better

Almost always, and the honest version of this section is long.

If a **trusted party may hold the data**, this is enormous overkill. A university that can
be trusted to answer "does this person hold a certificate?" needs an API endpoint, not a
SNARK. You are buying removal of a trusted party; if you were not going to remove one, you
have bought nothing and paid for it in setup ceremonies, artifact hosting, proving time and
a dependency tree only three people on your team can audit.

**Anonymous feedback** is usually better served by a survey tool. Real anonymous
whistleblowing needs a threat model that includes timing, writing style, and who pays for
the network connection — and this module addresses none of those.

**Where it genuinely earns its place:** private transactions (Zcash, Tornado Cash), where
the alternative really is a public ledger of everyone's finances; anonymous credentials at
scale, where a central verifier would learn every use of every credential; validity rollups
(zkSync, Scroll, StarkNet), where succinctness rather than privacy is the point and a proof
replaces re-executing thousands of transactions; and cross-chain light clients.

The pattern: zero-knowledge pays when the alternative requires either **publishing data
that must stay private** or **trusting a party who should not need to be trusted**. If
neither is true, use a database.

## What this does not fix

**The anonymity set is your privacy, and it is a social problem, not a mathematical one.**
With four members you have proved it was one of four. With one member you have proved it
was you, in public, with a signature. The contract publishes `memberCount()` where nobody
can miss it, because this is the thing everyone gets wrong. Every practical deconstruction
of a privacy protocol — every single one — attacks the set rather than the cryptography.

**The sender is public.** Somebody paid the gas. If that somebody is your only other
account, you have linked yourself. Production systems use relayers, which introduces a
party who now knows something — and the relayer knows your IP even if it never learns your
secret.

**Timing links things.** Enrol and post ten minutes apart while nobody else is using the
lab, and the correlation is obvious to anyone reading the chain in order. The defence is
waiting, and crowds, and neither is something the contract can provide.

**Metadata leaks.** Your RPC provider sees your IP with every call. The static artifacts
are fetched from our server, so our logs see that you loaded the prover. Writing style
identifies people startlingly well. None of this is touched by a SNARK.

**Lose the secret and the membership is gone.** No recovery, no admin override, no reset.
Your certificate is already marked as enrolled and cannot be used again. This is the honest
cost of "nobody can help you", which is the same sentence as "nobody can impersonate you",
and you do not get one without the other.

**The setup is only half a ceremony.** See above. On this chain, with these tokens, that is
acceptable. Say so out loud rather than quietly.

**One certificate is one membership — and that is the only Sybil defence there is.** It
comes from module 7, entirely outside the proof system. If certificates were easy to get,
the anonymity set would be full of one person wearing hats. Sybil resistance always comes
from somewhere outside the cryptography; the cryptography cannot manufacture it.

## Common mistakes

**An unconstrained public input.** The one the squaring line prevents. It fails open, it
produces no error, and every test you are likely to write still passes. Count your
constraints after changing a circuit.

**Reusing a nullifier across contexts.** `Poseidon(secret)` as a nullifier instead of
`Poseidon(secret, topic)` gives you one post *ever*, and worse, makes the nullifier equal
to your commitment — which links every post straight back to your enrolment. The domain
separator is doing real work.

**A weak secret.** `Math.random()` produces secrets an attacker can enumerate, and every
proof built on one is forgeable by anyone who notices. `app/src/zk/tree.js` refuses to
invent a secret without a cryptographic random source rather than falling back to
something that looks like it works.

**Trusting `verification_key.json` over the proving key.** The exported key and the `.zkey`
can drift. We hit exactly this: a rebuilt proving key with a stale exported verification
key produced proofs that failed for no visible reason. `scripts/gen-proof-fixture.mjs` now
derives the key from the `.zkey` itself, and rewrites the committed copy when they differ.

**Mock verifiers.** `PrivacyLab.t.sol` runs against a verifier that says yes to everything,
because a real proof in every test would make the suite unusable. Every test in that file
would pass against a contract with **no privacy at all**. That is why
`PrivacyLabProof.t.sol` exists and why it uses `vm.skip` rather than an early `return` —
our first version returned, and reported seven green ticks for tests that had run nothing.
A suite that reports success for work it did not do is worse than one that fails.

**Assuming a proof is a token.** Without signal binding it *is* one — anyone can lift it
and reuse it. Bind the proof to what it authorises.

**Forgetting the G2 coordinate swap.** snarkjs orders G2 points the way the pairing check
wants, not the way they appear in the proof. Do the swap by hand and you get a perfectly
valid proof that always fails on chain. Use `exportSolidityCallData` and parse it.

## Security checklist

- [ ] Every public input is genuinely constrained by the circuit.
- [ ] The nullifier includes a domain separator, and its scope is the scope you intended.
- [ ] Secrets come from a cryptographic random source, client side, and are never
      transmitted.
- [ ] The circuit, the contract and the client agree on hash, depth and empty-subtree
      constant — asserted by a test, not by inspection.
- [ ] Root history is bounded, and the window is defended rather than inherited.
- [ ] Nullifiers are stored before the event is emitted; no external call sits between.
- [ ] The verifier contract and the published proving artifacts come from the same build,
      and ship together.
- [ ] `memberCount()` is displayed anywhere a user is told this is anonymous.
- [ ] The phase-2 ceremony is described honestly in the documentation.
- [ ] No stamp, log, or side effect at prove time writes the prover's address anywhere.
- [ ] At least one test submits a real proof to the real verifier.

## Extend it

1. **Break it deliberately.** Delete the `signalSquare` line, rebuild, and demonstrate that
   a proof now verifies with a different message. Then write the fix and the test.
2. **Measure the anonymity set.** Enrol the whole class, then work out — from the chain
   alone — how much you can narrow down the author of each post using sender, timing and
   topic. Write it up as an attack report.
3. **Add a relayer.** A service that submits proofs so posters never pay gas. Then write
   down precisely what the relayer learns, and whether it is worse than what it fixed.
4. **Prove a different predicate.** "I hold a certificate in *this course*" — with the
   course as a public input, the certificate still hidden. Note what that narrows.
5. **Range proofs.** Prove a hidden value is over a threshold (age, grade, balance) without
   revealing it. This is where selective disclosure gets commercially interesting.
6. **Compare proof systems.** Rebuild with PLONK, which shares a universal setup and needs
   no per-circuit ceremony. Measure proof size, verification gas and proving time, and say
   which trade you would take and why.
7. **Run a real phase-2 ceremony** with three classmates contributing in sequence, publish
   the transcript, and have a fourth party verify it independently.

## Further reading

- [Circom documentation](https://docs.circom.io/) — start with the language tutorial.
- [snarkjs](https://github.com/iden3/snarkjs) — the full setup-to-verifier pipeline.
- [Vitalik Buterin, "Quadratic Arithmetic Programs: from Zero to Hero"](https://medium.com/@VitalikButerin/quadratic-arithmetic-programs-from-zero-to-hero-f6d558cea649)
  — the clearest explanation of how a program becomes constraints.
- [Groth16 paper](https://eprint.iacr.org/2016/260.pdf) — dense; read the introduction.
- [Semaphore](https://semaphore.pse.dev/) — the anonymous-signalling protocol this module
  follows. Read their design notes on nullifiers and external nullifiers.
- [Tornado Cash's circuits](https://github.com/tornadocash/tornado-core) — the reference
  implementation of commitment/nullifier mixing, and a case study in how a privacy set
  behaves in practice.
- [ZKProof Community Reference](https://docs.zkproof.org/) — on ceremonies, and on what
  "trusted setup" actually requires.
- Read about the [Zcash Powers of Tau ceremony](https://z.cash/technology/paramgen/) and
  compare it, honestly, with ours.

**Next:** [Back to the module index →](README.md)
