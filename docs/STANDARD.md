# The Trustville standard

Every module in Trustville has a first version: it works, it is deployed, it has tests and
a guide. That was the first phase. This page defines the second — what it takes for a module
to count as **market standard**, meaning a professional reviewer could read it next to the
production system it teaches and find the differences deliberate, documented and small.

It is written down because "production-ready" means whatever the person saying it needs it
to mean that week. A standard nobody wrote down is a standard nobody is held to.

## The four criteria

A module is at standard when **all four** hold for every contract it owns.

### 1 · Measured against a named reference

Each module teaches a pattern that exists in production somewhere. Name that implementation
and compare against it, line by line where it matters.

| Module | Reference implementation |
| --- | --- |
| 1 · Resident record | W3C DID Core / Verifiable Credentials data model; ENS registry |
| 2 · Soulbound Passport | ERC-721 + ERC-5192 (OpenZeppelin ERC721) |
| 3 · Town token | OpenZeppelin ERC20 + AccessControl; ERC20Capped |
| 4 · Product provenance | GS1 EPCIS event model |
| 5 · Escrow | OpenZeppelin `Escrow` / `ConditionalEscrow`; Kleros arbitration (ERC-792) |
| 6 · Sealed-bid auction | ENS's original Vickrey registrar (commit–reveal) |
| 7 · Verifiable certificates | W3C VC Data Model 2.0; Ethereum Attestation Service |
| 8 · Event tickets | OpenZeppelin ERC1155 |
| 9 · Property deeds | OpenZeppelin ERC721; ERC-4907 for rentals |
| 10 · Rent escrow | Pull-payment escrow; OpenZeppelin `PullPayment` (deprecated in v5 — say why) |
| 11 · Multisig treasury | Safe (Gnosis Safe) |
| 12 · DAO governance | OpenZeppelin Governor + TimelockController; Compound GovernorBravo |
| 13 · Charity | Milestone escrow; Gitcoin / Giveth patterns |
| 14 · Insurer and oracle | Chainlink OCR aggregation; Etherisc parametric insurance |
| 15 · Swap and lending | Uniswap V2; Compound / Aave v2; Uniswap V2 TWAP oracle |
| 16 · Zero-knowledge | Semaphore; Tornado Cash circuits |

The module's guide gains a **"Compared with production"** section: a table of what we match,
what we deliberately do differently and why, and what the production system adds that we do
not. A difference is fine. An *unexplained* difference is a finding.

**Deliberate weaknesses stay** where they are the lesson — module 15's spot-price oracle is
the whole point of module 15. They are held to a higher bar, not a lower one: stated at the
top of the guide, demonstrated by a test that exploits them, suppressed in Slither with a
written reason, and named alongside the production-grade alternative.

### 2 · Audit-grade tests

- [ ] A unit test for every external function, **including every revert path**
- [ ] Fuzz tests on every arithmetic path that touches value
- [ ] Invariant tests on every contract that holds value — money in equals money out plus
      balance, always, under any sequence of calls
- [ ] Coverage at or above **95% lines, 85% branches, 100% functions**
- [ ] Slither: no High, Medium or Low finding, unless suppressed in place with a reason:
      `// slither-disable-next-line <detector> -- <why this is safe here>`
- [ ] `forge lint` warnings read and either fixed or justified in a comment

The branch floor is the one that matters. An untested `else` is where the money leaves.

### 3 · Verified and documented

- [ ] `@title` and `@notice` on every contract
- [ ] NatSpec on every external and public function, event and custom error — `@notice` for
      the user, `@dev` for the reviewer, `@param` and `@return` where they are not obvious
- [ ] `@inheritdoc` on every override
- [ ] Source-verified on [explorer.didlab.org](https://explorer.didlab.org), with working
      Read and Write tabs
- [ ] Deployment recorded in `deployments/252501.json` and the deploy script reproducible

Custom errors deserve their NatSpec more than anything else: an error's `@notice` is the
sentence a student should see instead of `0x7a3f...`.

### 4 · Production UI

- [ ] Loading, empty and error states on every read — no blank panels
- [ ] Every revert decoded to a sentence a student can act on; raw hex never reaches the page
- [ ] Every disabled control says why it is disabled
- [ ] Usable at 360 px wide
- [ ] Every input labelled, keyboard-reachable, and passing an automated accessibility check
- [ ] No hardcoded addresses or chain ids; everything from configuration
- [ ] The transaction panel shows what happened on chain, in the terms the guide uses

## How it is enforced: the ratchet

Three of the four criteria are checked in CI by `scripts/gates.py`:

| Gate | Checks |
| --- | --- |
| `natspec` | contract `@title` / `@notice`; every function, event and error documented |
| `coverage` | the three floors above, per contract |
| `slither` | no Low+ finding; every suppression carries `-- reason` |

A gate that fails on day one for twenty-five contracts is a gate everyone learns to ignore.
So the gates are **strict only for contracts listed in `contracts/hardened.txt`**, and report
on everything else without failing. A module's hardening pull request adds its contracts to
that file in the same commit that brings them up to standard. From then on CI holds them
there, and they cannot quietly slide back.

```bash
npm run gates        # run all three, strict for hardened contracts
npm run gates:all    # where every contract stands — report only
npm run hooks        # install the pre-commit secrets check (do this once per clone)
```

Criteria 1 and 4 are reviewed by a person, against the checklists above, in the pull request.

### What is exempt, and why

- `Groth16Verifier.sol` and `PoseidonT3.sol` are generated — by snarkjs from the proving key,
  and from circomlib's compiled bytecode. Editing them would break the thing they exist to
  guarantee. They are proved correct by `PrivacyLabProof.t.sol`, which submits a real proof.
- A handful of members inherited from OpenZeppelin carry no NatSpec upstream
  (`DEFAULT_ADMIN_ROLE`, the Timelock roles, Governor's typehashes). They are exempt by name
  in `scripts/gates.py`. Our own overrides of inherited functions are not exempt.

## A module's hardening pull request

1. Write the **"Compared with production"** section of the guide first. It decides what the
   code changes are.
2. Change the contracts. Add the tests — reverts, fuzz, invariants — until the floors hold.
3. NatSpec everything. Triage every Slither finding: fix it, or suppress it with a reason.
4. Bring the stop's UI up to the checklist.
5. Add the contracts to `contracts/hardened.txt`. CI must be green.
6. Redeploy, grant `STAMPER_ROLE`, verify on the explorer, republish the site.

## Order

1. **The gates** — this page, the pre-commit hook, pinned toolchain, the three CI gates.
2. **Modules 1–3** — the registry, the passport and the token. Every other module stamps a
   passport whose address it holds as an immutable, so changing these means redeploying the
   whole town once. Doing them first means it happens once.
3. **Modules 4–16**, in order.

## Where each module stands

| # | Module | Standard |
| --- | --- | --- |
| 1 | Resident record | first version |
| 2 | Soulbound Passport | first version |
| 3 | Town token | first version |
| 4 | Product provenance | first version |
| 5 | Escrow | first version |
| 6 | Sealed-bid auction | first version |
| 7 | Verifiable certificates | first version |
| 8 | Event tickets | first version |
| 9 | Property deeds | first version |
| 10 | Rent escrow | first version |
| 11 | Multisig treasury | first version |
| 12 | DAO governance | first version |
| 13 | Charity | first version |
| 14 | Insurer and oracle | first version |
| 15 | Swap and lending | first version |
| 16 | Zero-knowledge | first version |

The baseline, measured when this page was written: 189 tests; 88.9% lines and 46.8% branches
across the project; 77 Slither findings outside generated code. Even module 16 — the newest
and most carefully tested — misses the NatSpec gate by 28 items and Slither by two. That is
the distance this phase covers.
