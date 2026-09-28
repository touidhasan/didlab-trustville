// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CertificateRegistry} from "./CertificateRegistry.sol";
import {IPoseidonT3} from "./PoseidonT3.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[4] calldata pubSignals
    ) external view returns (bool);
}

/// @title Trustville Privacy Lab  (module 16) — prove you qualify, reveal nothing else
/// @notice Module 7 ends by admitting what it cannot do: showing a certificate shows the
///         whole certificate — the course, the issuer, the holder — and ties it to an
///         address whose entire history is public. "I have a degree" and "here is my
///         degree, my name and everything else I have ever done on this chain" are not the
///         same sentence, and until now the town could only say the second.
///
/// @dev    Two steps, deliberately separated in time and in identity.
///
///         **Enrol.** Holding a valid certificate, you pick a secret, compute
///         `commitment = Poseidon(secret)` and enrol it. This transaction is public and
///         signed by you: everyone can see that address X enrolled. That is fine — it
///         proves you are entitled to be in the set, and the set is the point.
///
///         **Prove.** Later, from ANY address, you produce a zero-knowledge proof that you
///         know a secret whose commitment is a leaf under a root this contract knows. The
///         contract learns that someone in the set is speaking. It cannot learn which one.
///
///         What protects you is the size of the set, not the mathematics. A proof against a
///         tree with three members tells the reader it was one of three. The cryptography is
///         perfect and the anonymity is only as good as the crowd — which is the single most
///         misunderstood thing about this technology, and the reason this contract publishes
///         `memberCount()` where nobody can miss it.
contract PrivacyLab is Stamping {
    uint16 public constant MODULE_ID = 16;

    /// Tree depth. 2^16 = 65,536 members: a university, not a country. Raising it costs
    /// proving time and artifact size, not security.
    uint32 public constant LEVELS = 16;

    /// How many past roots stay valid. A proof is built against the root the prover saw;
    /// without a window, anyone enrolling between building a proof and sending it would
    /// invalidate it. 32 is roughly a few minutes of enrolments here.
    uint32 public constant ROOT_HISTORY = 32;

    uint256 public constant MAX_LENGTH = 280;

    /// The BN254 scalar field. Every value that enters the circuit must be smaller than
    /// this; a larger one wraps, and a wrapped value is a different value than the one the
    /// caller believed they sent.
    uint256 internal constant FIELD =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;

    IPoseidonT3 public immutable hasher;
    CertificateRegistry public immutable certificates;
    IGroth16Verifier public immutable verifier;

    uint256[LEVELS] public zeros;
    uint256[LEVELS] public filledSubtrees;
    uint256[ROOT_HISTORY] public roots;
    uint32 public currentRootIndex;
    uint32 public nextLeafIndex;

    mapping(uint256 => bool) public certificateEnrolled;
    mapping(uint256 => bool) public commitmentEnrolled;
    mapping(uint256 => bool) public nullifierUsed;

    /// Enrolment is public on purpose: it is the step that proves entitlement.
    event Enrolled(
        uint256 indexed certificateId, address indexed by, uint256 commitment, uint32 leafIndex
    );
    /// Posting is not. There is no author here, and that is the whole module.
    event AnonymousPost(uint256 indexed topic, uint256 indexed nullifierHash, string text);

    error NotTheHolder(address holder);
    error CertificateNotValid();
    error AlreadyEnrolled();
    error CommitmentAlreadyUsed();
    error NotInField();
    error TreeFull();
    error UnknownRoot();
    error NullifierAlreadyUsed();
    error BadProof();
    error EmptyNotice();
    error NoticeTooLong(uint256 length, uint256 max);
    error SignalMismatch();

    constructor(
        IPoseidonT3 hasher_,
        CertificateRegistry certificates_,
        IGroth16Verifier verifier_,
        TrustvillePassport passport_
    ) Stamping(passport_) {
        hasher = hasher_;
        certificates = certificates_;
        verifier = verifier_;

        // An empty subtree still has to hash to something, and that something must match
        // what the circuit computes for the same empty branch. Derived here once rather
        // than hardcoded, so changing LEVELS cannot leave a stale constant behind.
        uint256 zero = uint256(keccak256("trustville privacy lab")) % FIELD;
        for (uint32 i = 0; i < LEVELS; i++) {
            zeros[i] = zero;
            filledSubtrees[i] = zero;
            zero = hasher.poseidon([zero, zero]);
        }
        roots[0] = zero;
    }

    /* ------------------------------------------------------------------- enrolment */

    /// Join the set. Signed by the certificate holder, in public.
    ///
    /// One certificate buys one membership: without that, a single holder could enrol a
    /// thousand commitments and then speak a thousand times as a thousand apparent people.
    /// Sybil resistance has to come from somewhere outside the proof system, and here it
    /// comes from module 7.
    function enrol(uint256 certificateId, uint256 commitment) external returns (uint32 leafIndex) {
        if (!certificates.isValid(certificateId)) revert CertificateNotValid();

        address holder = certificates.get(certificateId).holder;
        if (holder != msg.sender) revert NotTheHolder(holder);
        if (certificateEnrolled[certificateId]) revert AlreadyEnrolled();
        if (commitment == 0 || commitment >= FIELD) revert NotInField();
        if (commitmentEnrolled[commitment]) revert CommitmentAlreadyUsed();

        certificateEnrolled[certificateId] = true;
        commitmentEnrolled[commitment] = true;
        leafIndex = _insert(commitment);

        emit Enrolled(certificateId, msg.sender, commitment, leafIndex);

        // Stamped HERE, not when you post. A stamp is written to your passport, and your
        // passport is your address -- stamping at post time would undo the anonymity the
        // post exists to provide. Enrolment is already public, so the stamp costs nothing.
        _stamp(msg.sender, MODULE_ID);
    }

    /* ---------------------------------------------------------------------- posting */

    /// Say something as a member of the set, without saying which member.
    ///
    /// `signalHash` binds the text to the proof. Drop it and a proof becomes a bearer token:
    /// anyone watching the mempool could lift it and attach their own message.
    function postAnonymously(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256 root,
        uint256 nullifierHash,
        uint256 topic,
        string calldata text
    ) external {
        uint256 len = bytes(text).length;
        if (len == 0) revert EmptyNotice();
        if (len > MAX_LENGTH) revert NoticeTooLong(len, MAX_LENGTH);

        if (!isKnownRoot(root)) revert UnknownRoot();
        if (nullifierUsed[nullifierHash]) revert NullifierAlreadyUsed();

        uint256 signalHash = hashSignal(text);
        if (!verifier.verifyProof(pA, pB, pC, [root, nullifierHash, topic, signalHash])) {
            revert BadProof();
        }

        // Effects before the event, and before anything else can run.
        nullifierUsed[nullifierHash] = true;
        emit AnonymousPost(topic, nullifierHash, text);
    }

    /// keccak of the message, shifted right 8 bits so it always fits in the field.
    ///
    /// Truncating to 248 bits costs nothing that matters -- this binds a message to a proof,
    /// it is not a commitment anyone is trying to break -- but the shift must be identical
    /// on both sides or every proof fails with nothing to show why.
    function hashSignal(string calldata text) public pure returns (uint256) {
        return uint256(keccak256(bytes(text))) >> 8;
    }

    /* ------------------------------------------------------------------------- tree */

    function _insert(uint256 leaf) internal returns (uint32 index) {
        uint32 i = nextLeafIndex;
        if (i == uint32(2) ** LEVELS) revert TreeFull();

        uint256 current = leaf;
        uint32 pos = i;

        for (uint32 level = 0; level < LEVELS; level++) {
            uint256 left;
            uint256 right;
            if (pos % 2 == 0) {
                // Left child: the right sibling is still empty, so remember this subtree
                // for when the sibling arrives.
                left = current;
                right = zeros[level];
                filledSubtrees[level] = current;
            } else {
                left = filledSubtrees[level];
                right = current;
            }
            current = hasher.poseidon([left, right]);
            pos /= 2;
        }

        currentRootIndex = (currentRootIndex + 1) % ROOT_HISTORY;
        roots[currentRootIndex] = current;
        nextLeafIndex = i + 1;
        return i;
    }

    function isKnownRoot(uint256 root) public view returns (bool) {
        if (root == 0) return false;
        uint32 i = currentRootIndex;
        for (uint32 n = 0; n < ROOT_HISTORY; n++) {
            if (roots[i] == root) return true;
            i = i == 0 ? ROOT_HISTORY - 1 : i - 1;
        }
        return false;
    }

    function currentRoot() external view returns (uint256) {
        return roots[currentRootIndex];
    }

    /// How many people you are hiding among. Read this before trusting the word anonymous.
    function memberCount() external view returns (uint32) {
        return nextLeafIndex;
    }
}
