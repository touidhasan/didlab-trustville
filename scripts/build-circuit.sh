#!/usr/bin/env bash
#
# Compile module 16's circuit, run the circuit-specific setup, and export the verifier.
#
#   ./scripts/build-circuit.sh                 # uses the Perpetual Powers of Tau
#   LOCAL_PTAU=1 ./scripts/build-circuit.sh    # generate phase 1 here instead (slow)
#
# Outputs:
#   contracts/src/Groth16Verifier.sol   the on-chain verifier
#   app/public/zk/membership.wasm       witness generator, fetched by the browser
#   app/public/zk/membership_final.zkey proving key, fetched by the browser
#   app/public/zk/verification_key.json for verifying off chain
#
# ---------------------------------------------------------------------------------------
#  ABOUT THE TRUSTED SETUP -- THE HALF THAT IS REAL, AND THE HALF THAT IS NOT
# ---------------------------------------------------------------------------------------
#
# Groth16 needs a trusted setup, and the setup produces secret randomness as a by-product.
# Anyone who keeps that randomness can forge a proof of anything, and no verifier can tell.
# The defence is a ceremony: many parties each contribute, and the result is sound as long
# as ONE of them discarded their contribution.
#
# The setup has two phases.
#
#   PHASE 1 is universal -- it depends only on circuit SIZE, so the whole industry shares
#   one. This script downloads the Perpetual Powers of Tau, a real ceremony with many
#   independent contributors and a public transcript. Nothing we do here can weaken it.
#
#   PHASE 2 is per circuit, so it has to happen here. Ours contributes once, from this
#   machine, unattended, with entropy from /dev/urandom, into a file committed to a public
#   repository. Every participant is us.
#
# So half the setup is genuinely trustworthy and half is theatre, and the module guide is
# explicit about which is which. For a teaching chain with worthless tokens, the theatre is
# fine. Shipping it anywhere real would be negligent. That distinction -- between a ceremony
# and the appearance of one -- is one of the more useful things module 16 has to teach.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/circuit"
CIRCOM="${CIRCOM:-circom}"

# 2^13 = 8192 constraints. The circuit uses 4,342, so this is the smallest that fits.
PTAU_POWER="${PTAU_POWER:-13}"
PTAU_URL="${PTAU_URL:-https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_${PTAU_POWER}.ptau}"

command -v "$CIRCOM" >/dev/null || {
  echo "circom not found. Install from https://docs.circom.io, or set CIRCOM=/path/to/circom"
  exit 1
}
[ -d "$ROOT/node_modules/circomlib" ] || { echo "run npm install first"; exit 1; }

# snarkjs spawns one wasm worker per core and the phase-2 setup holds the whole proving key
# in memory. On a 16-core box with node's default heap this SEGFAULTS -- rc 139, a truncated
# zkey, and a later step failing with "Missing section 10", which looks like a corrupt
# download or bad hardware and is neither. Node needs to be told it may use the RAM the
# machine obviously has.
export NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=8192}"

snarkjs() { npx --prefix "$ROOT" snarkjs "$@"; }

mkdir -p "$OUT"
cd "$OUT"

echo "==> compiling the circuit"
"$CIRCOM" "$ROOT/circuits/membership.circom" --r1cs --wasm --sym -l "$ROOT/node_modules" -o "$OUT"

# ---------------------------------------------------------------- phase 1, or a stand-in
if [ ! -f pot_final.ptau ]; then
  if [ "${LOCAL_PTAU:-0}" = "1" ]; then
    echo
    echo "==> phase 1 LOCALLY. This is slow -- several minutes -- and produces a ceremony"
    echo "    with exactly one participant. Prefer the downloaded one."
    snarkjs powersoftau new bn128 "$PTAU_POWER" pot_0000.ptau > /dev/null
    snarkjs powersoftau contribute pot_0000.ptau pot_0001.ptau \
      --name="didlab development contribution" -e="$(head -c 64 /dev/urandom | base64)" > /dev/null
    snarkjs powersoftau prepare phase2 pot_0001.ptau pot_final.ptau > /dev/null
  else
    echo
    echo "==> fetching the Perpetual Powers of Tau (phase 1, a real ceremony)"
    echo "    $PTAU_URL"
    if ! curl -fSL --progress-bar -o pot_final.ptau "$PTAU_URL"; then
      rm -f pot_final.ptau
      echo
      echo "    Download failed. Falling back to a local phase 1 -- about twenty seconds,"
      echo "    and a ceremony with exactly one participant. Everything still works; the"
      echo "    setup is simply less trustworthy than it would have been, which the guide"
      echo "    already says about phase 2 and now says about phase 1 too on this machine."
      echo
      snarkjs powersoftau new bn128 "$PTAU_POWER" pot_0000.ptau > /dev/null
      snarkjs powersoftau contribute pot_0000.ptau pot_0001.ptau \
        --name="didlab development contribution" -e="$(head -c 64 /dev/urandom | base64)" > /dev/null
      snarkjs powersoftau prepare phase2 pot_0001.ptau pot_final.ptau > /dev/null
    fi
  fi
fi

# ------------------------------------------------------------------------------ phase 2
echo
echo "==> phase 2: the circuit-specific setup"

# Retried, because this step has segfaulted on our build machine several times -- exit 139,
# a truncated zkey, and everything downstream failing for reasons that point nowhere near
# the cause. Raising node's heap helped once and then did not, which is the behaviour of a
# flaky machine rather than a configuration problem. The same host also crashes solc
# intermittently, with the same shape. If this loop is ever needed, run a memtest.
setup_ok=0
for attempt in 1 2 3 4 5; do
  rm -f membership_0000.zkey
  if snarkjs groth16 setup membership.r1cs pot_final.ptau membership_0000.zkey > /dev/null 2>&1; then
    setup_ok=1
    [ "$attempt" -gt 1 ] && echo "    succeeded on attempt $attempt"
    break
  fi
  echo "    attempt $attempt failed (exit $?) -- retrying"
done
[ "$setup_ok" = "1" ] || {
  echo
  echo "groth16 setup failed five times. This machine is not producing a usable proving key."
  echo "Check dmesg for segfaults and run a memory test before trusting anything it builds."
  exit 1
}
snarkjs zkey contribute membership_0000.zkey membership_final.zkey \
  --name="didlab development contribution" -e="$(head -c 64 /dev/urandom | base64)" > /dev/null

echo "==> checking the setup against the circuit"
snarkjs zkey verify membership.r1cs pot_final.ptau membership_final.zkey

echo
echo "==> exporting"
snarkjs zkey export verificationkey membership_final.zkey verification_key.json > /dev/null
snarkjs zkey export solidityverifier membership_final.zkey Groth16Verifier.sol > /dev/null

# snarkjs emits an older pragma. Pin it so the file compiles with the rest of the project.
sed -i 's|^pragma solidity .*|pragma solidity 0.8.24;|' Groth16Verifier.sol
cp Groth16Verifier.sol "$ROOT/contracts/src/Groth16Verifier.sol"

mkdir -p "$ROOT/app/public/zk"
cp membership_js/membership.wasm "$ROOT/app/public/zk/membership.wasm"
cp membership_final.zkey "$ROOT/app/public/zk/membership_final.zkey"
cp verification_key.json "$ROOT/app/public/zk/verification_key.json"

echo
echo "artifacts the browser will fetch:"
ls -lh "$ROOT/app/public/zk"
echo
echo "verifier: contracts/src/Groth16Verifier.sol"
echo
echo "Phase 1 came from a real ceremony. Phase 2 did not. See"
echo "docs/modules/16-zero-knowledge.md before repeating this anywhere that matters."
