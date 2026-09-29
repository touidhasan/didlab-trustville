#!/usr/bin/env bash
#
# Look for anything shaped like a secret, in what git is about to publish.
#
#   scripts/check-secrets.sh            # every tracked file — what CI runs
#   scripts/check-secrets.sh --staged   # the index — what the pre-commit hook runs
#
# ONE script for both, on purpose. On 2026-09-28 three oracle private keys went into a
# public commit. CI's check would have caught them — after the push, when the keys were
# already public and permanent. A check that runs after publication is a notification, not
# a defence. The pre-commit hook runs this same file before the commit exists, and because
# CI runs it too, the two cannot drift apart.
#
# And the check had been failing on every push for weeks, because role hashes and anvil's
# well-known dev key look exactly like private keys. A check that is always red protects
# nothing — nobody reads it. So known-public values are allowlisted BY EXACT VALUE in
# scripts/secrets-allowlist.txt, each with the reason it is public. A new 64-hex string
# still fails, which is the whole point.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MODE="tree"
[ "${1:-}" = "--staged" ] && MODE="staged"
GREP=(git grep)
[ "$MODE" = "staged" ] && GREP=(git grep --cached)

ALLOW="$ROOT/scripts/secrets-allowlist.txt"
fail=0

# Paths whose 64-hex strings are public by construction. Kept deliberately short:
# excluding a directory turns the check off for everything anyone ever puts in it.
EXCLUDE=(
  ':!contracts/test'                      # test vectors, fixtures
  ':!contracts/broadcast'                 # forge's record of what was broadcast
  ':!dist' ':!*.lock' ':!**/package-lock.json'
  ':!app/src/abi/generated.js'            # ABIs
  ':!deployments'                         # contract addresses, block hashes
  ':!docs'                                # transaction hashes in the guides
  ':!contracts/src/PoseidonT3.sol'        # generated: circomlib bytecode
  ':!contracts/src/Groth16Verifier.sol'   # generated: snarkjs verifier constants
  ':!app/public/zk'                       # generated: proving artifacts
  ':!scripts/secrets-allowlist.txt'
)

# ------------------------------------------------------------ 1. key-shaped strings
# 64 hex characters, with or without 0x, is exactly what a secp256k1 private key looks like.
#
# The allowlist is read once, and matched from a here-string rather than a pipe: with
# pipefail on, `grep -q` exiting early can SIGPIPE the command feeding it, and the whole
# match reports failure — an allowlisted value that fails at random.
ALLOWED="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW" | awk '{print tolower($1)}' | sed 's/^0x//')"
allowed() {
  local v
  v="$(printf '%s' "$1" | tr 'A-F' 'a-f' | sed 's/^0x//')"
  grep -qxF "$v" <<< "$ALLOWED"
}

hits="$("${GREP[@]}" -nIoE '\b(0x)?[0-9a-fA-F]{64}\b' -- . "${EXCLUDE[@]}" 2>/dev/null || true)"
if [ -n "$hits" ]; then
  while IFS= read -r line; do
    value="${line##*:}"
    location="${line%:*}"
    if ! allowed "$value"; then
      echo "  key-shaped value  $location  ${value:0:10}…"
      fail=1
    fi
  done <<< "$hits"
fi

# ------------------------------------------------------- 2. field names that mean "key"
# `cast wallet new --json` writes "private_key"; env files write PRIVATE_KEY=. Either one
# next to a value is a key, whatever the file is called.
named="$("${GREP[@]}" -nIiE '(private_?key|mnemonic|seed_?phrase)["'"'"' ]*[:=]\s*["'"'"']?(0x)?[0-9a-fA-F]{16,}' \
  -- . "${EXCLUDE[@]}" 2>/dev/null || true)"
if [ -n "$named" ]; then
  # File and line only. Never echo the match: CI logs on a public repository are public,
  # and printing the key while complaining about it would publish it a second time.
  echo "$named" | cut -d: -f1,2 | sed 's/^/  named key  /'
  fail=1
fi

# ---------------------------------------------------------------- 3. file names alone
# Some files are wrong to commit whatever is in them.
if [ "$MODE" = "staged" ]; then
  files="$(git diff --cached --name-only --diff-filter=ACMR)"
else
  files="$(git ls-files)"
fi
bad_files="$(printf '%s\n' "$files" | grep -E '(^|/)\.env(\.[^/]*)?$|(^|/)keys/|\.key(\.json)?$|(^|/)keystore/' \
  | grep -vE '(^|/)\.env\.example$' || true)"
if [ -n "$bad_files" ]; then
  echo "$bad_files" | sed 's/^/  forbidden file  /'
  fail=1
fi

if [ "$fail" = 1 ]; then
  echo
  echo "Something that looks like a secret is about to be published."
  echo "If it is a key: remove it, and if it was EVER pushed, rotate it — history is permanent."
  echo "If it is public by design (a role hash, a well-known test key): add the exact value to"
  echo "scripts/secrets-allowlist.txt with the reason it is public."
  exit 1
fi

echo "secrets: nothing key-shaped in the $([ "$MODE" = staged ] && echo 'staged changes' || echo 'tracked tree')"
