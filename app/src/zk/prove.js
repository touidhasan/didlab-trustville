import { keccak256, toBytes } from 'viem';
import { buildTree, commitmentOf, nullifierOf, pathFor } from './tree.js';

/**
 * Build a Groth16 membership proof, in the browser, on the student's own machine.
 *
 * The secret never leaves this file. It is not sent to a server, it is not put in a
 * transaction, and nothing here talks to the network except the two fetches for the
 * circuit artifacts — which are served from this same origin, on purpose. Pulling snarkjs
 * or the proving key off a CDN would hand a third party the ability to ship code that
 * quietly phones the secret home, and no amount of zero-knowledge downstream would help.
 * In a privacy module, WHERE the proving code comes from is part of the design.
 */

const WASM = '/zk/membership.wasm';
const ZKEY = '/zk/membership_final.zkey';

/**
 * Must match `PrivacyLab.hashSignal` exactly: keccak256 of the UTF-8 bytes, shifted right
 * eight bits so the result always fits in the BN254 scalar field. Shift on one side only
 * and every proof fails with `BadProof`, which tells you nothing about which side.
 */
export const hashSignal = (text) => BigInt(keccak256(toBytes(text))) >> 8n;

/**
 * ~1.4 MB of JavaScript, loaded the first time someone actually proves something rather
 * than on every page view. `import()` makes Vite put it in its own chunk; the rest of the
 * town stays as light as it was.
 */
let snarkjsPromise;
const loadSnarkjs = () => (snarkjsPromise ??= import('snarkjs'));

/** Warm the cache while the student is still reading the form. Safe to call repeatedly. */
export function preload() {
  loadSnarkjs().catch(() => {});
  if (typeof fetch === 'function') {
    fetch(WASM).catch(() => {});
    fetch(ZKEY).catch(() => {});
  }
}

const hex = (v) => '0x' + BigInt(v).toString(16).padStart(64, '0');

/**
 * Prove: "I know a secret whose commitment is a leaf under `root`, my nullifier for this
 * topic is `nullifierHash`, and I am saying exactly this text."
 *
 * @param secret      the value only you know
 * @param topic       which conversation this post belongs to
 * @param text        the message, bound into the proof so nobody can lift it
 * @param leaves      every commitment enrolled so far, in insertion order
 * @param leafIndex   where yours sits in that list
 * @param onProgress  called with short status strings, because this takes a few seconds
 */
export async function buildProof({ secret, topic, text, leaves, leafIndex, onProgress = () => {} }) {
  if (leaves[leafIndex] !== commitmentOf(secret)) {
    // Worth failing loudly here rather than after a ten-second proof: an off-by-one in the
    // leaf index produces a witness the circuit rejects, and circom's error for that is
    // "Assert Failed" with a line number in a file the student has never opened.
    throw new Error(
      'your commitment is not the leaf at that index — the enrolment list and your secret disagree',
    );
  }

  onProgress('loading the prover');
  const snarkjs = await loadSnarkjs();

  onProgress('rebuilding the tree');
  const tree = buildTree(leaves);
  const { pathElements, pathIndices } = pathFor(tree, leafIndex);

  const signalHash = hashSignal(text);
  const nullifierHash = nullifierOf(secret, topic);

  const input = {
    root: tree.root.toString(),
    nullifierHash: nullifierHash.toString(),
    topic: topic.toString(),
    signalHash: signalHash.toString(),
    secret: secret.toString(),
    pathElements: pathElements.map(String),
    pathIndices: pathIndices.map(String),
  };

  onProgress('proving — this takes a few seconds');
  const started = Date.now();
  const { proof, publicSignals } = await snarkjs.groth16.fullProve(input, WASM, ZKEY);
  const seconds = (Date.now() - started) / 1000;

  // The circuit's public signal order has to match the order the contract passes them to
  // the verifier. Reorder either side and proofs fail for a reason no error message names.
  const expected = [input.root, input.nullifierHash, input.topic, input.signalHash];
  for (let i = 0; i < expected.length; i++) {
    if (publicSignals[i] !== expected[i]) {
      throw new Error(
        `public signal ${i} is ${publicSignals[i]}, expected ${expected[i]} — the circuit ` +
          'artifacts in /zk/ are from a different build than this app expects',
      );
    }
  }

  // snarkjs orders G2 coordinates the way the pairing check wants, which is not the order
  // they appear in the proof object. `exportSolidityCallData` performs the swap; doing it
  // by hand is a coin flip that produces a perfectly valid proof which always fails on
  // chain. Parse its output instead.
  const calldata = await snarkjs.groth16.exportSolidityCallData(proof, publicSignals);
  const n = calldata.replace(/[["\]\s]/g, '').split(',');

  return {
    pA: [hex(n[0]), hex(n[1])],
    pB: [
      [hex(n[2]), hex(n[3])],
      [hex(n[4]), hex(n[5])],
    ],
    pC: [hex(n[6]), hex(n[7])],
    root: tree.root,
    nullifierHash,
    signalHash,
    seconds,
  };
}
