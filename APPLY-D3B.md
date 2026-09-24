# Phase D3b — the Council (modules 11–12)

```bash
cd ~/didlab-trustville
unzip -o ~/trustville-d3b.zip
cd contracts && forge test           # expect 93 passing
cd .. && npm run sync-abi && npm run build
git add -A && git commit -m "D3b: Council — multisig treasury and governance"
git push
```

## Two contracts must be REDEPLOYED

- **VoteToken** now counts votes by timestamp instead of block number, so voting periods
  mean what they say on any chain. Nothing was wrapped in the old one, so this is free.
- **RentEscrow** now takes the claim window per lease, and the minimum term is 5 minutes.
  Any lease in the old contract stays there; students should start fresh ones.

```bash
cd contracts
export TOWN_ADMIN=0x4F4c46350c75caAA2F88a37b7b83b8ec47949fA5
forge script script/DeployHousing.s.sol --rpc-url didlab --account didlab-deployer \
  --sender 0xDD9857376feFd1F91D5D1df71c2Ab52aCE39013C --legacy --broadcast
```

That redeploys PropertyDeeds, RentEscrow and VoteToken. Deeds registered in the old
contract will disappear from the site — if you would rather keep them, tell me and I will
split the script so only RentEscrow and VoteToken move.

Then the Council, with lab-sized timings (override with VOTING_DELAY / VOTING_PERIOD /
TIMELOCK_DELAY in seconds):

```bash
forge script script/DeployCouncil.s.sol --rpc-url didlab --account didlab-deployer \
  --sender 0xDD9857376feFd1F91D5D1df71c2Ab52aCE39013C --legacy --broadcast
```

Both scripts print the admin-signed `cast send … --interactive` lines for STAMPER_ROLE.
Grant them for: PropertyDeeds, RentEscrow (new addresses) and TownTreasury.
The Governor and Timelock need no passport role.

## Give the Council something to spend

The Timelock holds the governed funds, so send it TVD:

```bash
cast send <TownToken> "transfer(address,uint256)" <TownTimelock> 500000000000000000000 \
  --rpc-url didlab --legacy --interactive
```

## Publish

```bash
cd .. && npm run build
git add -A && git commit -m "Deploy D3b to chain 252501" && git push
git tag d3b && git push --tags
# on didlab-dapp:
sudo dapp-deploy
```
