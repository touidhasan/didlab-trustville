#!/usr/bin/env bash
#
# Verify every deployed contract on Blockscout.
#
#   ./scripts/verify-all.sh                # every contract in deployments/<chain>.json
#   ./scripts/verify-all.sh TownSwap GrainLoans     # just these
#
# Why this exists, and why it is not `forge verify-contract`:
#
# Foundry's blockscout verifier posts to the Etherscan-compatible /api route. On this
# explorer that path is served by the Next.js FRONTEND, which returns its own 404 page --
# so forge reports "Failed to deserialize content: expected value at line 1 column 1",
# which is what a JSON parser says when handed HTML. The backend is reachable, just under
# /api/v2, so this script posts to Blockscout's v2 endpoint directly.
#
# Two details cost an hour to find, and both are silent:
#   1. The multipart part MUST carry `type=application/json`. curl defaults to
#      application/octet-stream and Blockscout answers "JSON files not found" -- which
#      sounds like a missing file and is really a wrong content type.
#   2. `contract_name` is the BARE name (TownToken), not forge's path:Name form.
#
# Verification is not cosmetic here. Unverified contracts mean no Read/Write tabs and raw
# selectors instead of method names in every transaction a student inspects -- which
# quietly undercuts a course built on "check it yourself on the explorer". It also gives
# the town admin a way to sign admin calls from MetaMask without exporting the key.
set -euo pipefail

CHAIN_ID="${CHAIN_ID:-252501}"
EXPLORER="${EXPLORER:-https://explorer.didlab.org}"
COMPILER="${COMPILER:-v0.8.24+commit.e11b9ed9}"
RUNS="${RUNS:-200}"
LICENSE="${LICENSE:-mit}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
deployments="$root/deployments/$CHAIN_ID.json"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v forge >/dev/null || { echo "forge not found"; exit 1; }
command -v jq    >/dev/null || { echo "jq not found"; exit 1; }
[ -f "$deployments" ] || { echo "no $deployments"; exit 1; }

if [ $# -gt 0 ]; then
  names=("$@")
else
  mapfile -t names < <(jq -r '.contracts | keys[]' "$deployments")
fi

is_verified() {
  curl -s "$EXPLORER/api/v2/smart-contracts/$1" | jq -r '.is_verified // false'
}

ok=0; skipped=0; failed=0

for name in "${names[@]}"; do
  address="$(jq -r --arg n "$name" '.contracts[$n] // empty' "$deployments")"
  if [ -z "$address" ]; then
    printf '%-22s %s\n' "$name" "not in deployments/$CHAIN_ID.json"
    failed=$((failed + 1)); continue
  fi

  if [ "$(is_verified "$address")" = "true" ]; then
    printf '%-22s %-44s already verified\n' "$name" "$address"
    skipped=$((skipped + 1)); continue
  fi

  src="src/$name.sol:$name"
  json="$work/$name.json"
  if ! (cd "$root/contracts" && forge verify-contract "$address" "$src" \
        --compiler-version "${COMPILER%%+*}" --num-of-optimizations "$RUNS" \
        --show-standard-json-input) > "$json" 2>"$work/$name.err"; then
    printf '%-22s %-44s could not build standard json (%s)\n' \
      "$name" "$address" "$(head -1 "$work/$name.err")"
    failed=$((failed + 1)); continue
  fi

  # A zero-length or non-JSON file here means forge wrote its error to stdout. Catch it
  # now rather than letting Blockscout report something vaguer.
  if ! jq -e '.sources' "$json" >/dev/null 2>&1; then
    printf '%-22s %-44s standard json has no sources\n' "$name" "$address"
    failed=$((failed + 1)); continue
  fi

  reply="$(curl -sS -X POST \
    "$EXPLORER/api/v2/smart-contracts/$address/verification/via/standard-input" \
    -F "compiler_version=$COMPILER" \
    -F "contract_name=$name" \
    -F "autodetect_constructor_args=true" \
    -F "license_type=$LICENSE" \
    -F "files[0]=@$json;type=application/json" || true)"

  if ! grep -q "verification started" <<<"$reply"; then
    printf '%-22s %-44s rejected: %s\n' "$name" "$address" "$(head -c 120 <<<"$reply")"
    failed=$((failed + 1)); continue
  fi

  # Verification is queued, so poll rather than trusting the 200.
  for _ in $(seq 1 20); do
    sleep 3
    [ "$(is_verified "$address")" = "true" ] && break
  done

  if [ "$(is_verified "$address")" = "true" ]; then
    printf '%-22s %-44s verified\n' "$name" "$address"
    ok=$((ok + 1))
  else
    printf '%-22s %-44s started but not verified after 60s\n' "$name" "$address"
    failed=$((failed + 1))
  fi
done

echo
echo "verified $ok, already done $skipped, failed $failed"
[ "$failed" -eq 0 ]
