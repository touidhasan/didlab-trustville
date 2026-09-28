pragma circom 2.1.9;

include "circomlib/circuits/poseidon.circom";

/// Picks which of two values goes left and which goes right, according to one path bit.
///
/// `s` must be 0 or 1 and the constraint below is what enforces it. Without that line a
/// malicious prover could pass s = 7 and the mux would compute something the verifier
/// still accepts -- the classic under-constrained circuit bug, and the reason "it works on
/// honest inputs" is not a test of a circuit.
template DualMux() {
    signal input in[2];
    signal input s;
    signal output out[2];

    s * (1 - s) === 0;

    out[0] <== (in[1] - in[0]) * s + in[0];
    out[1] <== (in[0] - in[1]) * s + in[1];
}

/// Proves `leaf` sits under `root`, without revealing where.
///
/// Walks up the tree hashing the current node with its sibling, in the order the path bit
/// dictates, and asserts the top equals the claimed root. The path is private, so the
/// verifier learns membership and nothing else -- that single property is what the whole
/// module rests on.
template MerkleTreeChecker(levels) {
    signal input leaf;
    signal input root;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    component selectors[levels];
    component hashers[levels];

    for (var i = 0; i < levels; i++) {
        selectors[i] = DualMux();
        selectors[i].in[0] <== i == 0 ? leaf : hashers[i - 1].out;
        selectors[i].in[1] <== pathElements[i];
        selectors[i].s <== pathIndices[i];

        hashers[i] = Poseidon(2);
        hashers[i].inputs[0] <== selectors[i].out[0];
        hashers[i].inputs[1] <== selectors[i].out[1];
    }

    root === hashers[levels - 1].out;
}
