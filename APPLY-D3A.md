# Phase D3a — Housing (modules 9–10) + voting wrapper

```bash
cd ~/didlab-trustville
unzip -o ~/trustville-d3a.zip
cd contracts && forge test            # expect 79 passing
cd .. && npm run sync-abi && npm run build
git add -A && git commit -m "D3a: Housing — deeds, rent escrow, voting wrapper"
git push
```

## Deploy

```bash
cd contracts
export TOWN_ADMIN=0x4F4c46350c75caAA2F88a37b7b83b8ec47949fA5
forge script script/DeployHousing.s.sol --rpc-url didlab \
  --account didlab-deployer --sender 0xDD9857376feFd1F91D5D1df71c2Ab52aCE39013C \
  --legacy --broadcast
```

The script prints the two admin-signed `cast send ... --interactive` lines for
STAMPER_ROLE (PropertyDeeds and RentEscrow). VoteToken needs no roles.

## Publish

```bash
cd .. && npm run build
git add -A && git commit -m "Deploy D3a to chain 252501" && git push
git tag d3a && git push --tags
# on didlab-dapp:
sudo dapp-deploy
```

## Worth knowing

- The town admin is the deeds **certifier** and the rent **arbiter**.
- Leases run 2 hours and the claim window is 1 hour, so a class can watch a whole lease.
  Both are constants in RentEscrow.sol if you want different timings.
- Give students enough TVD: a 100 TVD grant does not cover a 100 TVD deposit plus rent.
