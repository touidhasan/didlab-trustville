# Phase D2b — the College (modules 7–8)

Overlay for your existing clone. No `dist/` — you rebuild it.

```bash
cd ~/didlab-trustville
unzip -o ~/trustville-d2b.zip

cd contracts && forge test            # expect 59 passing
cd .. && npm run sync-abi && npm run build
git add -A && git commit -m "D2b: College — certificates and ERC-1155 tickets"
git push
```

## Deploy

```bash
cd contracts
forge script script/DeployCollege.s.sol --rpc-url didlab \
  --account didlab-deployer --sender 0xDD9857376feFd1F91D5D1df71c2Ab52aCE39013C \
  --legacy --broadcast
```

Then the admin-signed grants. To see the exact commands without signing anything:

```bash
forge script script/GrantCollegeRoles.s.sol --rpc-url didlab --legacy
```

It prints two ready-to-paste `cast send ... --interactive` lines (each prompts for the admin
key), or run the script itself with `--broadcast --account <admin-keystore>`.

## Publish

```bash
cd .. && npm run build
git add -A && git commit -m "Deploy D2b to chain 252501" && git push
git tag d2b && git push --tags
# on didlab-dapp:
sudo dapp-deploy
```

The README in this zip is updated too — it replaces the one you just committed, so check
`git diff README.md` before committing if you changed it yourself.
