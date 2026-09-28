// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";
import {Groth16Verifier} from "../src/Groth16Verifier.sol";
import {IPoseidonT3, PoseidonT3} from "../src/PoseidonT3.sol";
import {IGroth16Verifier, PrivacyLab} from "../src/PrivacyLab.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// The only test that proves the whole thing works.
///
/// PrivacyLab.t.sol exercises the contract's rules against a mock verifier that says yes to
/// everything. Every test in it would pass against a contract with no privacy at all. This
/// one submits a REAL proof, produced by the real circuit, to the real generated verifier.
///
/// Four implementations have to agree exactly or nothing here passes:
///   circuits/merkle.circom        the tree as the circuit computes it
///   contracts/src/PrivacyLab.sol  the tree as the chain computes it
///   app/src/zk/tree.js            the tree as the browser computes it
///   Groth16Verifier.sol           generated from the proving key
///
/// Run `node scripts/gen-proof-fixture.mjs` after `npm run circuit` to refresh the fixture.
/// It is skipped rather than failed when the fixture is absent, so a fresh clone can run
/// the suite before building a 2.6 MB proving key.
contract PrivacyLabProofTest is Test {
    string constant FIXTURE = "test/fixtures/membership-proof.json";

    ResidentRegistry residents;
    TrustvillePassport passport;
    CertificateRegistry certs;
    IPoseidonT3 hasher;
    PrivacyLab lab;

    address admin = makeAddr("admin");
    address issuer = makeAddr("issuer");
    address relayer = makeAddr("relayer");

    string json;
    bool available;

    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;
    uint256 root;
    uint256 nullifierHash;
    uint256 topic;
    string message;

    function setUp() public {
        try vm.readFile(FIXTURE) returns (string memory contents) {
            json = contents;
            available = bytes(contents).length > 0;
        } catch {
            available = false;
        }
        if (!available) return;

        residents = new ResidentRegistry(admin);
        passport = new TrustvillePassport(admin, residents);
        certs = new CertificateRegistry(residents, passport);
        hasher = PoseidonT3.deploy();
        lab = new PrivacyLab(
            hasher, certs, IGroth16Verifier(address(new Groth16Verifier())), passport
        );

        vm.prank(issuer);
        residents.register(keccak256("issuer"));

        // Enrol every leaf from the fixture, in the same order, so the contract builds the
        // identical tree. Each needs its own certificate -- one certificate, one membership.
        uint256[] memory leaves = vm.parseJsonUintArray(json, ".leaves");
        for (uint256 i = 0; i < leaves.length; i++) {
            address who = address(uint160(0x5000 + i));
            vm.prank(who);
            residents.register(keccak256(abi.encodePacked("resident", i)));
            vm.prank(issuer);
            uint256 certId = certs.issue(who, "CS 5590", keccak256(abi.encodePacked("doc", i)));
            vm.prank(who);
            lab.enrol(certId, leaves[i]);
        }

        root = vm.parseJsonUint(json, ".root");
        nullifierHash = vm.parseJsonUint(json, ".nullifierHash");
        topic = vm.parseJsonUint(json, ".topic");
        message = vm.parseJsonString(json, ".message");

        uint256[] memory a = vm.parseJsonUintArray(json, ".pA");
        uint256[] memory b0 = vm.parseJsonUintArray(json, ".pB[0]");
        uint256[] memory b1 = vm.parseJsonUintArray(json, ".pB[1]");
        uint256[] memory c = vm.parseJsonUintArray(json, ".pC");
        pA = [a[0], a[1]];
        pB = [[b0[0], b0[1]], [b1[0], b1[1]]];
        pC = [c[0], c[1]];
    }

    /// Reports these as SKIPPED rather than passed when the fixture is missing.
    ///
    /// The first version returned early instead, so a clone with no proving key showed seven
    /// green ticks for tests that had run nothing. A suite that reports success for work it
    /// did not do is worse than one that fails: it is the mock-verifier problem again, one
    /// level up.
    modifier withFixture() {
        vm.skip(!available);
        _;
    }

    /// The cross-check that makes every later failure legible. If the chain and the
    /// JavaScript disagree about the root, everything downstream fails as BadProof, which
    /// says nothing. This says exactly what is wrong.
    function test_TheChainAndTheJavascriptAgreeOnTheRoot() public withFixture {
        assertEq(lab.currentRoot(), root, "contract tree != tree.js tree");
    }

    function test_ARealProofIsAccepted() public withFixture {
        vm.prank(relayer);
        lab.postAnonymously(pA, pB, pC, root, nullifierHash, topic, message);
        assertTrue(lab.nullifierUsed(nullifierHash), "nullifier not recorded");
    }

    /// The post carries no author. That is the entire module, asserted.
    function test_ThePostNamesNobody() public withFixture {
        vm.recordLogs();
        vm.prank(relayer);
        lab.postAnonymously(pA, pB, pC, root, nullifierHash, topic, message);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("AnonymousPost(uint256,uint256,string)");
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] != sig) continue;
            found = true;
            // topics: [signature, topic, nullifierHash]. No address anywhere.
            assertEq(logs[i].topics.length, 3, "unexpected indexed fields");
            assertEq(uint256(logs[i].topics[1]), topic);
            assertEq(uint256(logs[i].topics[2]), nullifierHash);
        }
        assertTrue(found, "no AnonymousPost emitted");
    }

    /// Change one character and the proof is worthless. Without the signalHash binding in
    /// the circuit, anyone watching the mempool could lift this proof and attach their own
    /// message -- so this test is the one guarding that constraint.
    function test_TheProofDoesNotTransferToAnotherMessage() public withFixture {
        vm.expectRevert(PrivacyLab.BadProof.selector);
        lab.postAnonymously(pA, pB, pC, root, nullifierHash, topic, string.concat(message, "!"));
    }

    function test_AProofCannotBeReplayed() public withFixture {
        lab.postAnonymously(pA, pB, pC, root, nullifierHash, topic, message);
        vm.expectRevert(PrivacyLab.NullifierAlreadyUsed.selector);
        lab.postAnonymously(pA, pB, pC, root, nullifierHash, topic, message);
    }

    /// A tampered proof must fail at the verifier, not sail past it.
    function test_ATamperedProofIsRejected() public withFixture {
        uint256[2] memory bad = [pA[0], pA[1] ^ 1];
        vm.expectRevert();
        lab.postAnonymously(bad, pB, pC, root, nullifierHash, topic, message);
    }

    /// Claiming a different nullifier than the one proved breaks the circuit's binding.
    function test_TheNullifierCannotBeSwapped() public withFixture {
        vm.expectRevert(PrivacyLab.BadProof.selector);
        lab.postAnonymously(pA, pB, pC, root, nullifierHash + 1, topic, message);
    }
}
