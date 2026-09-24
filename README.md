# DIDLab Trustville

**Live:** https://dapp.didlab.org · **Chain:** DIDLab (ID 252501) · **Explorer:** https://explorer.didlab.org

Trustville is a fictional small town where every everyday trust problem is solved with a
blockchain feature. It is the showcase dApp for the DIDLab Blockchain course: students walk
through the town with their own MetaMask wallet, watch each transaction land on chain, and
fork any module as the starting point for their group project.

## Objective

One story, many modules — so students see how the pieces fit together rather than meeting
each standard in isolation. By the end of the walk-through a student should be able to:

1. Say when a blockchain is the right tool, and when a normal database is better. Every
   module states both.
2. Read what a transaction actually did: events, state changes, gas, and who signed it.
3. Use the core standards — ERC-20, ERC-721, ERC-1155, soulbound tokens (ERC-5192),
   role-based access control, commit–reveal, escrow, oracles.
4. Separate on-chain from off-chain data, and explain what should never go on a public
   ledger.
5. Deploy their own version of a module and host it on their group subdomain.

Two design rules run through everything: **personal data never goes on chain** (only
hashes), and **privileges belong to contracts, not people** (no human can mint the town
currency).

## Status

| Phase | Modules | State |
| --- | --- | --- |
| D0 | Site, wallet onboarding, notice board | Live |
| D1 | 1–3 Resident identity, Passport, Town token | Live · tag `d1` |
| D2a | 4–6 Provenance, Escrow, Sealed-bid auction | Live · tag `d2a` |
| D2b | 7–8 Certificates, ERC-1155 tickets | Live · tag `d2b` |
| D3a | 9–10 Property deeds, Rent escrow (+ voting wrapper) | Live · tag `d3a` |
| D3b | 11–12 Multisig treasury, DAO governance | Built, awaiting deploy |
| D4 | 13–15 Charity, Insurer, DeFi | Planned |
| D5 | Instructor progress view, lab handouts | Planned |
| D6 | 16 Zero-knowledge proofs | Stretch |

### Deployed on chain 252501

| Contract | Address | Phase |
| --- | --- | --- |
| ResidentRegistry | `0x30209DE180f649ea47C959dD611404ca87fdbF5e` | D1 |
| TrustvillePassport | `0xA046E4D575cE37D5024893f590D3FF74690e8211` | D1 |
| TownToken (TVD) | `0x9a17Fa48aa787De5CB470214D28af89CaFf7762c` | D1 |
| TownBank | `0x01A0bfEe1875c78Adf1179797e5f06212Bf6d8A4` | D1 |
| ProductRegistry | `0x242A011d333c2FEfb3cF82ab8104916282CaD8Ce` | D2a |
| TownEscrow | `0x397B5783AD4De4004274be14544cd186eABa57D5` | D2a |
| SealedAuction | `0x029Ad3CD878071c6389bA891EfFB42C88c14b04a` | D2a |
| CertificateRegistry | `0x42F5198AfAa5F639D3F20eB02ff89311FC51F7a4` | D2b |
| EventTickets | `0x2Ed7004e740bC7a415B8A030723224ca5419cd94` | D2b |
| PropertyDeeds | `0x25628280fFE164F8De37150F34F536b129885078` | D3a |
| RentEscrow | *redeployed in D3b — durations are now per-lease* | D3a |
| VoteToken | *redeployed in D3b — timestamp clock* | D3a |

The app reads these from `deployments/252501.json`; redeploying a contract never needs a
code change.

## Stops and modules

| Stop | Modules | Phase |
| --- | --- | --- |
| Town Hall | 1 Resident record · 2 Soulbound Passport | D1 |
| Bank | 3 Town token (ERC-20) · 15 Swap and lending | D1 / D4 |
| Market | 4 Product provenance · 5 Escrow · 6 Sealed-bid auction | D2a |
| College | 7 Verifiable certificates · 8 Event tickets (ERC-1155) | D2b |
| Housing | 9 Property deeds (ERC-721) · 10 Rent escrow | D3a |
| Council | 11 Multisig treasury · 12 DAO governance | D3b |
| Charity | 13 Milestone crowdfunding | D4 |
| Insurer | 14 Parametric insurance (oracle) | D4 |
| Privacy Lab | 16 Zero-knowledge proofs | D6 (stretch) |

Each module ships with a guide in [`docs/modules/`](docs/modules/): the problem, why a
blockchain (and when not), the design, steps to try it, three suggested extensions, and a
security checklist.

## Repository layout

```
app/                    Vite + React frontend (source)
contracts/              Foundry project: src/ contracts, test/ tests, script/ deployments
deployments/252501.json Contract addresses on the DIDLab chain (read by the app)
services/               API, indexer, oracle (added in D4)
proxmox/                scripts that create the VM hosting dapp.didlab.org
docs/modules/           One guide per module
scripts/sync-abi.mjs    Copies compiled ABIs into the frontend
dist/                   Built site — this is what the web host publishes
```

## Develop

```bash
npm run setup        # install app dependencies
npm run dev          # local dev server at http://localhost:5173
npm run build        # build into dist/  (commit dist/ before pushing)
```

Contracts (requires [Foundry](https://book.getfoundry.sh)):

```bash
cd contracts
forge install foundry-rs/forge-std --no-git                          # first time only
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-git    # first time only
forge build && forge test                                            # 40 tests
cd .. && npm run sync-abi        # refresh app/src/abi/generated.js after changing a contract
```

## Keys

Two keys, never one. Gas is free on this chain, but ownership is not: a leaked key that can
mint the town currency or issue certificates hands over the whole town.

| Key | Holds | Lives in |
| --- | --- | --- |
| Deployer | Nothing once a deployment finishes | Encrypted Foundry keystore on the build machine |
| Town admin (`TOWN_ADMIN`) | `DEFAULT_ADMIN_ROLE` on every contract, escrow arbiter | MetaMask, or a keystore you unlock deliberately |

`DeployTown.s.sol` deploys with the deployer as temporary admin, wires the contracts to
each other, grants everything to `TOWN_ADMIN`, renounces its own roles, and then asserts
all of that — a broken handover fails the deployment instead of shipping quietly.

```bash
cast wallet import didlab-deployer --interactive     # once
cd contracts
export TOWN_ADMIN=0xYourAdminAddress
forge script script/DeployTown.s.sol --rpc-url didlab --account didlab-deployer --legacy --broadcast
```

`--legacy` is required: the DIDLab chain does not support EIP-1559.

Because the deployer ends up with no roles, wiring a **new** module contract into the
Passport is necessarily a second, admin-signed step:

```bash
forge script script/DeployMarket.s.sol     --rpc-url didlab --account didlab-deployer --legacy --broadcast
forge script script/GrantMarketRoles.s.sol --rpc-url didlab --legacy                  # prints the calls
forge script script/GrantMarketRoles.s.sol --rpc-url didlab --legacy --broadcast --account <admin>
```

Never commit a private key, and never put one in a tenant's Env tab.

## Hosting

The site is static: the frontend talks to the chain from the student's browser, so no server
holds a key or signs anything.

- **Dedicated VM (current)** — `proxmox/create-dapp-vm.sh` builds a Debian VM with nginx,
  atomic releases, `dapp-deploy` / `dapp-rollback`, and a Cloudflare tunnel. See
  [`proxmox/README.md`](proxmox/README.md).
- **cPanel tenant** — Tenants → **dapp** → Deploy from Git, which publishes `dist/` with no
  build step on the server.

## Release

1. Deploy or update contracts; the scripts write addresses into `deployments/252501.json`.
2. `npm run build` and commit `dist/` — the host publishes files and does not build.
3. `git push`, then `git tag <phase> && git push --tags`.
4. On the web host: `sudo dapp-deploy` (or redeploy from Git in cPanel).
5. `sudo dapp-rollback` returns to the previous release if something is wrong.

## Timings

Durations are bounded, not fixed, so the same contracts suit a lab and a homework week.

| Setting | Bounds | Lab default |
| --- | --- | --- |
| Lease term | 5 min – 365 days | 15 min |
| Deposit claim window | 2 min – 30 days | 5 min |
| Auction commit / reveal | 30 s – 7 days each | 5 min |
| Governance delay / voting / timelock | set at deployment | 1 min / 10 min / 2 min |

Governance timings are deployment-time settings: `VOTING_DELAY`, `VOTING_PERIOD` and
`TIMELOCK_DELAY` (seconds) on `DeployCouncil.s.sol`.

## Rules

- This repository is public. Never commit private keys, mnemonics or `.env` files.
- Only textbook designs live here. Research-stage designs stay out.
- No student names or grades on chain; wallet addresses stay pseudonymous.
- Anything students can call is open by design and rate-limited by the contract, so a
  griefer costs the class nothing.

## License

MIT — see [LICENSE](LICENSE). Fork it, break it, rebuild it.
