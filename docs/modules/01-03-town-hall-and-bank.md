# Modules 1–3 · Resident identity, Passport, Town token

## The problem

Trustville needs to know who its residents are, keep a record of what they have done, and
run a local currency — without a clerk who can quietly edit the ledger, and without holding
everyone's personal documents.

## Why a blockchain

| Need | Blockchain answer | When a database is better |
| --- | --- | --- |
| A record nobody can silently alter | Append-only state, every change signed and public | One organisation everyone already trusts, with an audit log |
| Proof you completed something, that you cannot sell | Soulbound token (ERC-5192) | An internal HR system nobody outside needs to verify |
| Currency other systems can read | ERC-20, understood by every wallet | Points inside one app |
| Privacy of the underlying documents | Store the hash, keep the document off chain | You need to search the documents themselves |

## Design

```
ResidentRegistry      who belongs to the town; holds credential HASHES, never documents
TrustvillePassport    soulbound ERC-721, one per resident, stamped per module
TownToken (TVD)       ERC-20 town currency, capped supply
TownBank              hands out one welcome grant per resident; holds MINTER_ROLE
```

Two rules shape the whole design:

1. **Personal data never goes on chain.** You keep your credential document. The registry
   stores `keccak256(document)`, which proves the document has not changed and reveals nothing.
2. **Privileges belong to contracts, not people.** `TownBank` holds `MINTER_ROLE` on the token
   and `STAMPER_ROLE` on the passport, so "one grant per resident" is enforced by code. No
   human — not even the town admin — can mint TVD.

### Keys

| Key | Holds | Where it lives |
| --- | --- | --- |
| Deployer | Nothing once deployment finishes | Env var or keystore on the build machine |
| Town admin | `DEFAULT_ADMIN_ROLE` + `REGISTRAR_ROLE` | Encrypted Foundry keystore |

`script/DeployTown.s.sol` deploys with the deployer as temporary admin, wires the roles,
grants everything to `TOWN_ADMIN`, then renounces its own roles and asserts the result.
`test_DeployerHoldsNothingAfterHandover` fails the build if that ever breaks.

## Try it

1. Finish the wallet setup on the home page (MetaMask, chain 252501, TRUST from the faucet).
2. **Become a resident.** Watch the panel: `ResidentRegistered` carries your address and the
   credential hash — and nothing else.
3. **Mint your passport.** Note two stamps arrive in the same transaction, and `Locked` tells
   wallets it can never be transferred.
4. **Claim the welcome grant.** One transaction mints TVD *and* stamps your passport, because
   the Bank holds both roles.
5. **Send TVD to a classmate**, then look up both addresses on explorer.didlab.org.
6. Try to break it: claim twice, register twice, or send your passport to a friend. Read the
   error the contract gives back — refusals are as much a feature as successes.

## Extend it

1. Add an expiry to residency, so records lapse at the end of a term unless renewed.
2. Make the welcome grant decrease as more residents claim it, and explain the incentive it creates.
3. Add a `PAUSER_ROLE` that can freeze claims during an incident, with a test proving a paused
   Bank refuses to mint.

## Security checklist

- [ ] Does any function change state before checking `isResident`?
- [ ] Can a student call a role-gated function directly, bypassing the UI? Write the test.
- [ ] Is state written before external calls (reentrancy)?
- [ ] After your own deploy, does the deployer hold zero roles?
- [ ] Does any event leak data that should have stayed off chain?
