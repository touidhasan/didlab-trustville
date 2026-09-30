#!/usr/bin/env bash
# Stand up the whole of Trustville on your own machine.
#
#   ./scripts/local-town.sh
#
# Starts a local chain, deploys the whole town (the Privacy Lab included), starts three
# rain reporters, points the site at it and opens it. No faucet, no permissions, no waiting for blocks — and nothing you do touches
# the public chain.
#
# Stop it with Ctrl-C; the chain and everything on it disappear with it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RPC=http://127.0.0.1:8545
CHAIN_ID=31337
# anvil's first account. It is a published test key with no value anywhere — never put
# anything real behind it.
KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

need() { command -v "$1" >/dev/null || { echo "missing: $1 — see the README's Prerequisites"; exit 1; }; }
need anvil; need forge; need node; need npm

ENVFILE="$ROOT/app/.env"
BACKUP="$ROOT/app/.env.before-local-town"

# Take the chain down AND take the .env with it.
#
# This script writes app/.env so the site talks to the throwaway chain. Leaving that file
# behind is how a production build silently ships pointing at 127.0.0.1:8545 -- which is
# exactly what happened on 2026-09-26: dapp.didlab.org went out built for a local anvil
# chain that had been dead for days, and the site correctly reported the chain as
# unreachable while everyone looked at the wrong end of the wire.
cleanup() {
  for pid in ${REPORTER_PIDS:-}; do kill "$pid" 2>/dev/null || true; done
  [ -n "${ANVIL_PID:-}" ] && kill "$ANVIL_PID" 2>/dev/null || true
  if [ -f "$ENVFILE" ] && grep -q 'written by scripts/local-town.sh' "$ENVFILE" 2>/dev/null; then
    rm -f "$ENVFILE"
    if [ -f "$BACKUP" ]; then mv "$BACKUP" "$ENVFILE"; fi
    echo "==> app/.env removed — the next build targets DIDLab again"
  fi
  return 0 # this runs on EXIT; a stray non-zero here would fake a failed run
}
trap cleanup EXIT

echo "==> starting a local chain"
anvil --chain-id "$CHAIN_ID" --silent &
ANVIL_PID=$!

for i in $(seq 1 40); do
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
  sleep 0.25
  [ "$i" = 40 ] && { echo "anvil did not come up"; exit 1; }
done

# Compile first, and visibly. The first run builds ~106 files, which takes a while and
# looks like a hang if it happens behind a --silent flag.
echo "==> compiling (first run takes a minute)"
cd "$ROOT/contracts"
forge build --skip test

echo "==> deploying the town"
# Unset so DeployAll makes the deployer the admin, which is what lets one script both
# deploy a contract and grant it the right to stamp passports.
# --slow sends one transaction at a time and waits for each receipt. Without it forge
# fires all 40 at once, anvil drops a handful from its mempool, and the run hangs waiting
# for a receipt that will never arrive.
env -u TOWN_ADMIN forge script script/DeployAll.s.sol \
  --rpc-url "$RPC" --broadcast --slow --private-key "$KEY"

# The two things DeployAll leaves out, so the local town really is the whole town: the
# Privacy Lab (module 16) and someone to report the weather (module 14). Without them the
# fallback laptop in class stops two modules short.
echo "==> the Privacy Lab"
forge script script/DeployPrivacyLab.s.sol --rpc-url "$RPC" --broadcast --slow --private-key "$KEY" >/dev/null
J="$ROOT/deployments/$CHAIN_ID.json"
addr() { node -e "console.log(require(process.argv[1]).contracts[process.argv[2]])" "$J" "$1"; }
cast send --private-key "$KEY" "$(addr TrustvillePassport)" "grantRole(bytes32,address)" \
  "$(cast keccak STAMPER_ROLE)" "$(addr PrivacyLab)" --rpc-url "$RPC" >/dev/null

echo "==> three rain reporters"
# anvil's accounts 7, 8 and 9, derived from the phrase every anvil prints on startup —
# public, worthless anywhere else, exactly like KEY above.
ANVIL_WORDS="test test test test test test test test test test test junk"
cd "$ROOT/services/rain-reporter"
[ -d node_modules ] || npm install --silent
REPORTER_PIDS=""
for i in 7 8 9; do
  rk="$(cast wallet private-key "$ANVIL_WORDS" "$i")"
  cast send --private-key "$KEY" "$(addr RainOracle)" "grantRole(bytes32,address)" \
    "$(cast keccak REPORTER_ROLE)" "$(cast wallet address --private-key "$rk")" --rpc-url "$RPC" >/dev/null
  station=$([ "$i" = 7 ] && echo north || { [ "$i" = 8 ] && echo east || echo west; })
  PRIVATE_KEY="$rk" node reporter.mjs --rpc "$RPC" --station "$station" > "/tmp/trustville-reporter-$station.log" 2>&1 &
  REPORTER_PIDS="$REPORTER_PIDS $!"
done

echo "==> wiring the frontend"
cd "$ROOT"
[ -d app/node_modules ] || npm run setup
npm run sync-abi

[ -f "$ENVFILE" ] && ! grep -q 'written by scripts/local-town.sh' "$ENVFILE" && mv "$ENVFILE" "$BACKUP"

cat > "$ENVFILE" <<EOF
# written by scripts/local-town.sh — delete this file to go back to DIDLab
VITE_CHAIN_ID=$CHAIN_ID
VITE_RPC_URL=$RPC
VITE_CHAIN_NAME=Local Trustville
VITE_CURRENCY_SYMBOL=ETH
VITE_CURRENCY_NAME=Ether
VITE_FAUCET_URL=
VITE_EXPLORER_URL=
EOF

cat <<'EOF'

================================================================
Trustville is running on your own chain.

In MetaMask, add a network:
  RPC      http://127.0.0.1:8545
  Chain ID 31337
  Currency ETH

Then import this account, which deployed the town and is its admin:
  0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

It is anvil's published test key. It is worthless everywhere, which is
exactly why it is safe to paste — and why you should never use a key you
found in a README on a chain that matters.

Ctrl-C stops the chain and everything on it.
================================================================

EOF

# --host 127.0.0.1 forces IPv4. Vite's default binds "localhost", which on an
# IPv6-first box is [::1] only -- so an SSH tunnel forwarding 127.0.0.1 gets
# "connection refused" while the site looks perfectly happy in the terminal.
npm run dev -- --host 127.0.0.1
