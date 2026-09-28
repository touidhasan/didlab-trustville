import { poseidon1, poseidon2 } from 'poseidon-lite';

/**
 * The same incremental Merkle tree PrivacyLab.sol builds, in JavaScript.
 *
 * There are three implementations of this tree in the project and they must agree exactly:
 * the circuit (circuits/merkle.circom), the contract (contracts/src/PrivacyLab.sol) and this
 * one. A single mismatched constant produces a proof that is mathematically perfect and
 * verifies against a root nobody has — the error message for which is `UnknownRoot`, or
 * worse, `BadProof`, neither of which points anywhere useful.
 *
 * So: `ZERO` is asserted against the contract in Solidity (see PrivacyLab.t.sol), the hash
 * is checked against circomlib's own implementation in the fixture generator, and `LEVELS`
 * appears once in each of the three places with a test that would fail if they drifted.
 */

/** BN254 scalar field. Everything entering the circuit must be smaller than this. */
export const FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

export const LEVELS = 16;

/**
 * `uint256(keccak256("trustville privacy lab")) % FIELD`, matching the contract's
 * constructor. Hardcoded here rather than recomputed, because pulling a keccak
 * implementation into the browser bundle to derive a constant would be silly — and
 * PrivacyLab.t.sol asserts the contract's value equals this one, so drift fails a test
 * rather than a proof.
 */
export const ZERO = 12555648292192804865851842650875475074529953264741711734414181847757353101767n;

/** The leaf you enrol: only the holder of `secret` can produce it. */
export const commitmentOf = (secret) => poseidon1([secret]);

/** One nullifier per secret per topic — which is what stops a second post on the same topic. */
export const nullifierOf = (secret, topic) => poseidon2([secret, topic]);

/** Precomputed hashes of empty subtrees, one per level. */
export function zeros(levels = LEVELS) {
  const out = [];
  let z = ZERO;
  for (let i = 0; i < levels; i++) {
    out.push(z);
    z = poseidon2([z, z]);
  }
  return out;
}

/**
 * Rebuild the tree from the leaves in insertion order, and produce the path for one of them.
 *
 * Rebuilding from scratch is the honest thing to do at this scale: 65,536 leaves is a few
 * hundred milliseconds and no state can go stale. A production system keeps an incremental
 * tree in an indexer and hands the client a path — which is faster, and introduces a party
 * who knows which leaf you asked about. Worth noticing that the convenient architecture is
 * the one that quietly removes the privacy.
 */
export function buildTree(leaves, levels = LEVELS) {
  const z = zeros(levels);
  let layer = leaves.slice();
  const layers = [layer];

  for (let level = 0; level < levels; level++) {
    const next = [];
    for (let i = 0; i < layer.length; i += 2) {
      const left = layer[i];
      const right = i + 1 < layer.length ? layer[i + 1] : z[level];
      next.push(poseidon2([left, right]));
    }
    if (next.length === 0) next.push(poseidon2([z[level], z[level]]));
    layers.push(next);
    layer = next;
  }

  return { layers, root: layer[0], zeros: z, levels };
}

/** The sibling at each level, and which side the current node sat on. */
export function pathFor(tree, leafIndex) {
  const pathElements = [];
  const pathIndices = [];
  let index = leafIndex;

  for (let level = 0; level < tree.levels; level++) {
    const layer = tree.layers[level];
    const isRight = index % 2 === 1;
    const siblingIndex = isRight ? index - 1 : index + 1;
    const sibling = siblingIndex < layer.length ? layer[siblingIndex] : tree.zeros[level];

    pathElements.push(sibling);
    pathIndices.push(isRight ? 1 : 0);
    index = Math.floor(index / 2);
  }

  return { pathElements, pathIndices };
}

/** A fresh secret. `crypto.getRandomValues` in a browser, `webcrypto` under Node. */
export function randomSecret() {
  const bytes = new Uint8Array(31); // 248 bits, always below the field modulus
  (globalThis.crypto ?? require('node:crypto').webcrypto).getRandomValues(bytes);
  let out = 0n;
  for (const b of bytes) out = (out << 8n) | BigInt(b);
  return out;
}

/** Everything the circuit needs, assembled. */
export function witnessInput({ secret, topic, signalHash, leaves, leafIndex, levels = LEVELS }) {
  const tree = buildTree(leaves, levels);
  const { pathElements, pathIndices } = pathFor(tree, leafIndex);
  return {
    root: tree.root.toString(),
    nullifierHash: nullifierOf(secret, topic).toString(),
    topic: topic.toString(),
    signalHash: signalHash.toString(),
    secret: secret.toString(),
    pathElements: pathElements.map(String),
    pathIndices: pathIndices.map(String),
  };
}
