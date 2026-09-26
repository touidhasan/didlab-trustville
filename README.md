# DIDLab Trustville

**Live:** https://dapp.didlab.org · **Chain:** DIDLab (ID 252501) · **Explorer:** https://explorer.didlab.org

Trustville is a small town where every everyday trust problem is solved with a blockchain
feature. It is the showcase dApp for the DIDLab blockchain course: you walk through the
town with your own MetaMask wallet, watch each transaction land on chain, and fork any
module as the starting point for your own project.

Fifteen of sixteen modules are live. Every one of them states plainly what a blockchain
buys you — and where a normal database would have done the job better.

---

## For students: just walk the town

You do not need to clone anything.

1. Install [MetaMask](https://metamask.io).
2. Open **https://dapp.didlab.org** and press **Connect**. The site offers to add the
   DIDLab network for you.
3. You will have no TRUST, which is the chain's gas. Follow the link to the faucet — your
   instructor has the code it asks for. One drip lasts the whole course.
4. Work down the page. Each stop is a module; each module has a guide in
   [`docs/modules/`](docs/modules/).

Your **Passport** is a soulbound token that collects a stamp for each module you complete.
It cannot be transferred, sold or given away — which is the point of module 2.

---

## What you should be able to do by the end

1. Say when a blockchain is the right tool, and when it is not. Every module argues both
   sides.
2. Read what a transaction actually did: events, state changes, gas, and who signed it.
3. Use the standards — ERC-20, ERC-721, ERC-1155, soulbound tokens (ERC-5192), role-based
   access control, commit–reveal, escrow, oracles, governance, AMMs.
4. Separate on-chain from off-chain data, and explain what must never go on a public ledger.
5. Deploy your own version of a module and host it on your group's subdomain.

Two design rules run through everything: **personal data never goes on chain** (only
hashes), and **privileges belong to contracts, not people** (no human can mint the town
currency).

---

## Run the whole town on your own machine

One command gives you a private Trustville: your own chain, all 22 contracts, the site
pointed at it. No faucet, no permissions, nothing you do touches the public chain.

### Prerequisites

| | |
| --- | --- |
| [Node.js](https://nodejs.org) 20+ | `node --version` |
| [Foundry](https://book.getfoundry.sh/getting-started/installation) | `forge --version` — provides `forge`, `cast` and `anvil` |
| git | |

On Windows, use WSL2 — Foundry targets Linux and macOS.

### Go

```bash
git clone https://github.com/touidhasan/didlab-trustville
cd didlab-trustville

cd contracts
forge install foundry-rs/forge-std --no-git
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-git
cd ..

npm run local
```

That starts a local chain, deploys the town, wires the frontend and serves it at
http://localhost:5173. The script prints the network settings for MetaMask and the test
account that owns everything. Ctrl-C stops the chain and takes the town with it.

Because the deployer is also the admin on a local chain, everything is granted in one
script. That is *not* how the public deployment works — see **Keys** below.

### Running the site against the live DIDLab chain instead

```bash
npm run setup
npm run dev
```

With no `app/.env` the site talks to DIDLab and the real contracts, which is what
dapp.didlab.org serves. Copy `app/.env.example` to `app/.env` to point it anywhere else;
addresses are read from `deployments/<chainId>.json`, chosen by chain id, so switching
chains is configuration rather than a code edit.

---

## The stops

| Stop | Modules | Guides |
| --- | --- | --- |
| Town Hall | 1 Resident record · 2 Soulbound Passport · 3 Town token | [1](docs/modules/01-resident-record.md) · [2](docs/modules/02-soulbound-passport.md) · [3](docs/modules/03-town-token.md) |
| Market | 4 Provenance · 5 Escrow · 6 Sealed-bid auction | [4](docs/modules/04-product-provenance.md) · [5](docs/modules/05-escrow.md) · [6](docs/modules/06-sealed-bid-auction.md) |
| College | 7 Verifiable certificates · 8 Event tickets (ERC-1155) | [7](docs/modules/07-verifiable-certificates.md) · [8](docs/modules/08-event-tickets.md) |
| Housing | 9 Property deeds (ERC-721) · 10 Rent escrow | [9](docs/modules/09-property-deeds.md) · [10](docs/modules/10-rent-escrow.md) |
| Council | 11 Multisig treasury · 12 DAO governance | [11](docs/modules/11-multisig-treasury.md) · [12](docs/modules/12-dao-governance.md) |
| Charity | 13 Milestone crowdfunding | [13](docs/modules/13-charity.md) |
| Insurer | 14 Parametric insurance and the oracle problem | [14](docs/modules/14-insurer.md) |
| Exchange | 15 Swap, liquidity and lending ⚠ | [15](docs/modules/15-defi.md) |
| Privacy Lab | 16 Zero-knowledge proofs | planned |

**[Every module has its own guide →](docs/modules/)** Each one follows the same shape: the
problem, the idea, the vocabulary, how it works, the two or three lines that carry the
design, a walkthrough on the live site, the events it emits, when a plain database would
have been better, what it does **not** fix, common mistakes, a security checklist, and
exercises with traps in them.

Two of them are worth reading even if you never run the code. [Module 14](docs/modules/14-insurer.md)
is where the chain stops being self-contained and has to trust somebody about the weather.
[Module 15](docs/modules/15-defi.md) ships a **deliberately vulnerable** lending contract
and a test that exploits it successfully — the bug is the lesson.

---

## Status

| Phase | Modules | State |
| --- | --- | --- |
| D0 | Site, wallet onboarding, notice board | Live |
| D1 | 1–3 Resident identity, Passport, Town token | Live · `d1` |
| D2a | 4–6 Provenance, Escrow, Sealed-bid auction | Live · `d2a` |
| D2b | 7–8 Certificates, ERC-1155 tickets | Live · `d2b` |
| D3a | 9–10 Property deeds, Rent escrow | Live · `d3a` |
| D3b | 11–12 Multisig treasury, DAO governance | Live · `d3b` |
| D4a | 13 Milestone crowdfunding | Live · `d4a` |
| D4b | 14 Oracle and parametric insurance | Live |
| D4c | 15 Swap and lending | Live |
| D5 | Lab handouts, instructor progress view | Planned |
| D6 | 16 Zero-knowledge proofs | Stretch |

Deployed addresses live in [`deployments/252501.json`](deployments/252501.json), which the
app reads at build time. **Redeploying a contract needs no code change — but it does need
two follow-ups that fail silently if you forget:** grant the new address `STAMPER_ROLE` on
the Passport, and rebuild `dist/`, because addresses are baked in at build time.

---

## Repository layout

```
app/                    Vite + React frontend (source)
contracts/src/          The contracts
contracts/test/         Foundry tests, ~139 of them
contracts/script/       Deployment scripts, one per phase, plus DeployAll
deployments/<id>.json   Contract addresses per chain — read by the app
services/rain-reporter/ The oracle nodes for module 14
docs/modules/           One guide per module
scripts/local-town.sh   Local chain + full deployment + dev server
scripts/sync-abi.mjs    Copies compiled ABIs into the frontend
dist/                   Built site — this is what the web host publishes
```

---

## Tests

```bash
npm test                                   # all of them
cd contracts && FOUNDRY_PROFILE=test forge test --match-contract CouncilTest -vv
```

Tests run without the optimizer (see the comment in `foundry.toml`); deployments use the
optimized build. A few are worth reading as documentation:

- `test_ATTACK_InflateTheCollateralPriceAndWalkAway` — the module 15 exploit, working.
- `test_ImpermanentLossIsRealAndMeasurable` — puts a number on what liquidity provision costs.
- `test_OneLiarCannotMoveTheAnswer` / `test_AMajorityOfReportersControlsTheAnswer` — what
  M-of-N buys, and what it does not.
- `test_TimelockIsOwnedByNobody` — the property that makes the DAO's vote mean something.

---

## Deploying your own town

On a fresh chain, one script does everything:

```bash
cd contracts
forge script script/DeployAll.s.sol --rpc-url <rpc> --broadcast --slow --private-key <key>
```

`--slow` matters: it sends one transaction at a time. Without it, forge fires all forty
at once and a local node will quietly drop some.

On DIDLab, deploy phase by phase instead, because the public deployment deliberately splits
deploying from granting:

```bash
export TOWN_ADMIN=0xYourAdminAddress
forge script script/DeployTown.s.sol     --rpc-url didlab --account didlab-deployer \
  --sender <deployer> --legacy --slow --gas-estimate-multiplier 105 --broadcast
# then DeployMarket, DeployCollege, DeployHousing, DeployCouncil,
#      DeployCharity, DeployInsurer, DeployDefi
```

Each script ends by printing the admin-signed `grantRole` commands it could not run itself.

Two things this chain will teach you the hard way:

- `--legacy` is required — DIDLab has no EIP-1559 fee market.
- Gas estimates are squeezed from both sides. `TownGovernor` costs 4,039,001 gas against a
  4,700,000 block limit, so Foundry's default 130% padding is rejected outright; but 105%
  is too tight for `renounceRole`, which earns a storage refund the estimator nets out.
  Deploys need a low multiplier, state-clearing calls need a high one or an explicit
  `--gas-limit`. `FinishCouncil.s.sol` exists because a script once ran out of gas on its
  last step and left a Timelock half-wired.

---

## Keys

Three keys, each able to do one thing. That separation is the whole security model, and it
was learned the hard way: the town admin key spent months doubling as the faucet's signing
key, which meant an unattended server process could have minted the currency.
`RotateAdmin.s.sol` is what fixed it, and it is worth reading before you design your own.

| Key | Can do | Lives in |
| --- | --- | --- |
| Deployer | Nothing, once a deployment finishes | Encrypted Foundry keystore on the build machine |
| Town admin | `DEFAULT_ADMIN_ROLE` everywhere; arbiter, registrar, certifier | MetaMask. Admin actions only — never a demo account, never on a server |
| Service keys | Report the weather. Send gas. Nothing else | Root-owned env files on the machine that runs them |

`DeployTown.s.sol` deploys with the deployer as temporary admin, wires the contracts, grants
everything to `TOWN_ADMIN`, renounces its own roles, and then **asserts** all of that — a
broken handover fails the deployment instead of shipping quietly.

Because the deployer ends up with nothing, wiring a new module into the Passport is
necessarily a second, admin-signed step. That is friction on purpose.

**Never commit a private key, a mnemonic or an `.env` file.** This repository is public.

---

## Services

Module 14 needs oracle nodes: three processes, three keys, each reading its own simulated
rain gauge. See [`services/rain-reporter/`](services/rain-reporter/README.md) — including
how to stage a lying reporter in class and watch the median absorb it.

Gas comes from the DIDLab faucet, which is shared with the rest of the platform.

---

## Release

1. Deploy or update contracts; the scripts write addresses into `deployments/252501.json`.
2. `npm run sync-abi && npm run build`, and commit `dist/` — the host publishes files and
   does not build.
3. `git push`, then tag **after** confirming the site is up. Never move a published tag:
   every clone that already has it will refuse to fetch.
4. On the web host: `sudo dapp-deploy`. `sudo dapp-rollback` returns to the previous release.

---

## Timings

Durations are bounded, not fixed, so the same contracts suit a lab and a homework week.

| Setting | Bounds | Lab default |
| --- | --- | --- |
| Lease term | 5 min – 365 days | 15 min |
| Deposit claim window | 2 min – 30 days | 5 min |
| Auction commit / reveal | 30 s – 7 days each | 5 min |
| Governance delay / voting / timelock | set at deployment | 1 min / 10 min / 2 min |
| Oracle period | ≥ 60 s | 10 min |
| Grain harvest cooldown | 1 min – 7 days | 10 min |

---

## Rules

- This repository is public. Never commit private keys, mnemonics or `.env` files.
- Only textbook designs live here. Research-stage designs stay out.
- No student names or grades on chain; wallet addresses stay pseudonymous.
- Anything students can call is open by design and rate-limited by the contract, so a
  griefer costs the class nothing.

---

## License

MIT — see [LICENSE](LICENSE). Fork it, break it, rebuild it.
