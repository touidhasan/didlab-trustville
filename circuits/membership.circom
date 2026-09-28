pragma circom 2.1.9;

include "circomlib/circuits/poseidon.circom";
include "merkle.circom";

/// Trustville Privacy Lab (module 16) -- prove membership, reveal nothing else.
///
/// Module 7 anchors certificates on chain and says plainly that it cannot do selective
/// disclosure: showing a certificate shows the whole thing, and links it to an address with
/// a full transaction history. This circuit is the missing half.
///
/// The prover knows a `secret`. Its Poseidon commitment was enrolled into a Merkle tree by
/// somebody holding a valid certificate. The proof says: "a commitment I can open is in the
/// tree whose root is `root`." It does not say which leaf, and the verifier cannot tell.
///
/// Public signals, and why each one is public:
///   root           the set being proved against -- the contract checks it is a root it knows
///   nullifierHash  Poseidon(secret, topic). Same secret, same topic, same nullifier, so the
///                  contract can refuse a second use. Different topic, different nullifier,
///                  so posts on unrelated topics are not linked
///   topic          which conversation this proof is for
///   signalHash     the message, hashed. Bound below so a relayer cannot take a valid proof
///                  and attach it to different text
///
/// Private: the secret and the Merkle path. Both must stay private or the anonymity is gone.
template Membership(levels) {
    signal input root;
    signal input nullifierHash;
    signal input topic;
    signal input signalHash;

    signal input secret;
    signal input pathElements[levels];
    signal input pathIndices[levels];

    // The leaf is the commitment, and only the holder of `secret` can produce it.
    component commitmentHasher = Poseidon(1);
    commitmentHasher.inputs[0] <== secret;

    // The nullifier is derived from the same secret, so it cannot be faked or varied --
    // one secret yields exactly one nullifier per topic.
    component nullifierHasher = Poseidon(2);
    nullifierHasher.inputs[0] <== secret;
    nullifierHasher.inputs[1] <== topic;
    nullifierHasher.out === nullifierHash;

    component tree = MerkleTreeChecker(levels);
    tree.leaf <== commitmentHasher.out;
    tree.root <== root;
    for (var i = 0; i < levels; i++) {
        tree.pathElements[i] <== pathElements[i];
        tree.pathIndices[i] <== pathIndices[i];
    }

    // Bind the message to the proof without constraining its value.
    //
    // A public input that no constraint touches is optimised away, and the proof would then
    // verify against ANY message -- so anyone watching the mempool could take your proof and
    // post something else with it. Squaring it is the cheapest way to make the message part
    // of what was proved. This trick is Semaphore's, and it is worth understanding rather
    // than copying: the lesson is that a public signal only means something if the circuit
    // uses it.
    signal signalSquare;
    signalSquare <== signalHash * signalHash;
}

// 16 levels: 65,536 members, which is a university rather than a country, and keeps the
// proving key small enough to ship to a browser. Raising it costs artifact size and proving
// time, not security.
component main {public [root, nullifierHash, topic, signalHash]} = Membership(16);
