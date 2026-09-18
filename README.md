# DIDLab Trustville

**Live:** https://dapp.didlab.org · **Chain:** DIDLab (ID 252501) · **Explorer:** https://explorer.didlab.org

Trustville is a fictional small town where every everyday trust problem is solved with a blockchain feature. It is the showcase dApp for the DIDLab Blockchain course: students use it with their own MetaMask wallet, trace every transaction on the explorer, and fork any module as the starting point for their group project.

## Stops and modules

| Stop | Modules | Phase |
| --- | --- | --- |
| Town Hall | 1 Resident identity (DID + VC) · 2 Soulbound Passport | D1 |
| Bank | 3 Town token (ERC-20) · 15 Swap and lending | D1 / D4 |
| Market | 4 Product provenance · 5 Escrow · 6 Sealed-bid auction | D2 |
| College | 7 Verifiable certificates · 8 Event tickets (ERC-1155) | D2 |
| Housing | 9 Property deeds (ERC-721) · 10 Rent escrow | D3 |
| Council | 11 Multisig treasury · 12 DAO governance | D3 |
| Charity | 13 Milestone crowdfunding | D4 |
| Insurer | 14 Parametric insurance (oracle) | D4 |
| Privacy Lab | 16 Zero-knowledge proofs | D6 (stretch) |

## Repository layout

```
app/                    Vite + React frontend (source)
contracts/              Foundry project; one folder per module under src/
deployments/252501.json Contract addresses on the DIDLab chain (read by the app)
services/               API, indexer, oracle (added in D4)
docs/modules/           One README per module
dist/                   Built site — this is what cPanel publishes
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
forge build && forge test
cd .. && npm run sync-abi        # refresh app/src/abi/generated.js after changing a contract
```

## Keys

Two keys, never one:

| Key | Holds | Lives in |
| --- | --- | --- |
| Deployer | Nothing after a deploy finishes | Env var or keystore on the build machine |
| Town admin (`TOWN_ADMIN`) | `DEFAULT_ADMIN_ROLE` on every contract | Encrypted Foundry keystore |

Create the deployer key once, encrypted:

```bash
cast wallet import didlab-deployer --interactive
```

Deploy the town (the script hands all privileges to `TOWN_ADMIN`, then renounces its own):

```bash
cd contracts
export TOWN_ADMIN=0xYourAdminAddress
forge script script/DeployTown.s.sol --rpc-url didlab --broadcast --account didlab-deployer
```

Addresses are written into `deployments/252501.json` automatically. Never commit a private
key, and never put one in the cPanel tenant's Env tab.

## Release

1. Deploy or update contracts, then record addresses in `deployments/252501.json`.
2. `npm run build` and commit `dist/`.
3. `git push origin main`.
4. cPanel → Tenants → **dapp** → Deploy → repository URL, branch `main` → **Deploy**.
5. Tag the release: `git tag d0 && git push --tags`.

## Rules

- This repository is public. Never commit private keys, mnemonics or `.env` files.
- Only textbook designs live here. Research-stage designs stay out.
- No student names or grades on chain.

## License

MIT — see [LICENSE](LICENSE).
