#!/usr/bin/env node
/**
 * Produce a real proof and write it where the Foundry test can read it.
 *
 *   npm run circuit          # first -- this needs the artifacts
 *   node scripts/gen-proof-fixture.mjs
 *   cd contracts && forge test --match-contract PrivacyLabProof
 *
 * Why a fixture rather than proving inside the test: Foundry cannot run snarkjs, and
 * generating a Groth16 proof takes a second or two -- fine once, unbearable in a suite that
 * runs on every save. So the slow half happens here and the fast half happens in Solidity.
 *
 * What this exists to catch is the failure mode that unit tests with a mock verifier cannot
 * see at all. Four independent implementations have to agree exactly:
 *
 *   circuits/merkle.circom      the tree as the circuit computes it
 *   contracts/src/PrivacyLab.sol the tree as the chain computes it
 *   app/src/zk/tree.js           the tree as the browser computes it
 *   Groth16Verifier.sol          the verifier generated from the proving key
 *
 * One mismatched constant anywhere and you get a proof that is mathematically perfect and
 * verifies against a root nobody has. The test asserts the contract's root EQUALS the root
 * this script computed, before it ever submits the proof -- so a disagreement fails with
 * "roots differ" rather than an opaque BadProof.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { keccak256, toBytes } from 'viem';
import { buildTree, commitmentOf, nullifierOf, pathFor, randomSecret } from '../app/src/zk/tree.js';

const require = createRequire(import.meta.url);
const snarkjs = require('snarkjs');

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const WASM = join(ROOT, 'app/public/zk/membership.wasm');
const ZKEY = join(ROOT, 'app/public/zk/membership_final.zkey');
const OUT = join(ROOT, 'contracts/test/fixtures/membership-proof.json');

/** Must match PrivacyLab.hashSignal: keccak256 of the bytes, shifted right 8 bits. */
const hashSignal = (text) => BigInt(keccak256(toBytes(text))) >> 8n;

const hex = (v) => '0x' + BigInt(v).toString(16).padStart(64, '0');

const MESSAGE = 'the lifts in the science block have been broken for a month';
const TOPIC = 7n;
const MEMBERS = 4;
const ME = 2; // prove as the third member, so the path exercises both sides of the tree

const secrets = Array.from({ length: MEMBERS }, () => randomSecret());
const leaves = secrets.map(commitmentOf);
const tree = buildTree(leaves);
const { pathElements, pathIndices } = pathFor(tree, ME);

const signalHash = hashSignal(MESSAGE);
const nullifierHash = nullifierOf(secrets[ME], TOPIC);

const input = {
  root: tree.root.toString(),
  nullifierHash: nullifierHash.toString(),
  topic: TOPIC.toString(),
  signalHash: signalHash.toString(),
  secret: secrets[ME].toString(),
  pathElements: pathElements.map(String),
  pathIndices: pathIndices.map(String),
};

console.log(`proving membership of ${MEMBERS}, as member ${ME}…`);
const started = Date.now();
const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);
console.log(`proved in ${((Date.now() - started) / 1000).toFixed(1)}s`);

// The order the circuit emits public signals in must match the order the contract passes
// them. Checked here so a reordering fails loudly at fixture time.
const expected = [input.root, input.nullifierHash, input.topic, input.signalHash];
for (let i = 0; i < expected.length; i++) {
  if (publicSignals[i] !== expected[i]) {
    throw new Error(
      `public signal ${i} is ${publicSignals[i]}, expected ${expected[i]} — ` +
        'the circuit\'s public signal order no longer matches the contract',
    );
  }
}

// Verify off chain before writing it. If this fails, nothing downstream is worth debugging.
//
// The key is derived from the PROVING key here, not read from verification_key.json. Those
// two can drift -- a rebuilt zkey with a stale exported key is silent, and shows up as a
// proof that fails for no visible reason. Deriving it means this check tests the proof
// rather than the bookkeeping, and the committed file gets checked separately below.
const vk = await snarkjs.zKey.exportVerificationKey(ZKEY);
if (!(await snarkjs.groth16.verify(vk, publicSignals, proof))) {
  throw new Error(
    'the proof does not verify against a key derived from the proving key itself. ' +
      'The wasm and the zkey are probably from different compilations of the circuit — ' +
      'delete build/circuit and rerun npm run circuit.',
  );
}

// Now the bookkeeping. The browser and the off-chain tooling read this file, so a stale one
// breaks them while everything here looks fine.
const committedPath = join(ROOT, 'app/public/zk/verification_key.json');
const committed = require(committedPath);
if (JSON.stringify(committed) !== JSON.stringify(vk)) {
  console.warn('\napp/public/zk/verification_key.json did not match the proving key.');
  console.warn('Rewriting it from the zkey.\n');
  writeFileSync(committedPath, JSON.stringify(vk, null, 1) + '\n');
}

// snarkjs emits G2 points in the order the pairing check wants, which is NOT the order they
// appear in the proof. exportSolidityCallData does the swap; parsing its output is more
// reliable than doing it by hand, and getting it wrong yields a valid proof that always
// fails on chain.
const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
const nums = calldata.replace(/[["\]\s]/g, '').split(',');

const fixture = {
  message: MESSAGE,
  topic: hex(TOPIC),
  leaves: leaves.map(hex),
  leafIndex: ME,
  root: hex(tree.root),
  nullifierHash: hex(nullifierHash),
  signalHash: hex(signalHash),
  pA: [hex(nums[0]), hex(nums[1])],
  pB: [
    [hex(nums[2]), hex(nums[3])],
    [hex(nums[4]), hex(nums[5])],
  ],
  pC: [hex(nums[6]), hex(nums[7])],
};

mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, JSON.stringify(fixture, null, 2) + '\n');

console.log(`wrote ${OUT.replace(ROOT + '/', '')}`);
console.log(`  members      ${MEMBERS}`);
console.log(`  root         ${fixture.root}`);
console.log(`  nullifier    ${fixture.nullifierHash}`);
process.exit(0);
