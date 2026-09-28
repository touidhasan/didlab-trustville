// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {CertificateRegistry} from "../src/CertificateRegistry.sol";
import {IPoseidonT3, PoseidonT3} from "../src/PoseidonT3.sol";
import {IGroth16Verifier, PrivacyLab} from "../src/PrivacyLab.sol";
import {ResidentRegistry} from "../src/ResidentRegistry.sol";
import {TrustvillePassport} from "../src/TrustvillePassport.sol";

/// Says yes to everything, so these tests can exercise the contract's own rules without a
/// 30-second proof generation in the loop. The real verifier is exercised separately, in
/// PrivacyLabProof.t.sol, against a fixture produced by the actual circuit.
///
/// Worth being explicit about what this mock costs: every test in this file would pass
/// against a contract with no privacy at all. They test the bookkeeping, not the
/// cryptography, and a suite of only these would be a comfortable lie.
contract AlwaysYes is IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[4] calldata
    ) external pure returns (bool) {
        return true;
    }
}

contract AlwaysNo is IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata,
        uint256[2][2] calldata,
        uint256[2] calldata,
        uint256[4] calldata
    ) external pure returns (bool) {
        return false;
    }
}

contract PrivacyLabTest is Test {
    /// Mirrors app/src/zk/tree.js. If these ever disagree, every proof fails against a root
    /// nobody has -- so the assertion below is the cheapest insurance in the project.
    uint256 constant ZERO_IN_JS =
        12555648292192804865851842650875475074529953264741711734414181847757353101767;

    ResidentRegistry residents;
    TrustvillePassport passport;
    CertificateRegistry certs;
    IPoseidonT3 hasher;
    PrivacyLab lab;

    address admin = makeAddr("admin");
    address issuer = makeAddr("issuer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address stranger = makeAddr("stranger");

    uint256 aliceCert;
    uint256 bobCert;

    uint256[2] pA;
    uint256[2][2] pB;
    uint256[2] pC;

    function setUp() public {
        residents = new ResidentRegistry(admin);
        passport = new TrustvillePassport(admin, residents);
        certs = new CertificateRegistry(residents, passport);
        hasher = PoseidonT3.deploy();
        lab = new PrivacyLab(hasher, certs, new AlwaysYes(), passport);

        vm.prank(issuer);
        residents.register(keccak256("issuer"));
        vm.prank(alice);
        residents.register(keccak256("alice"));
        vm.prank(bob);
        residents.register(keccak256("bob"));

        vm.prank(issuer);
        aliceCert = certs.issue(alice, "CS 5590", keccak256("alice-doc"));
        vm.prank(issuer);
        bobCert = certs.issue(bob, "CS 5590", keccak256("bob-doc"));
    }

    /* ------------------------------------------------------------ the three-way pact */

    function test_TheZeroValueMatchesTheJavascript() public view {
        assertEq(lab.zeros(0), ZERO_IN_JS, "contract and app/src/zk/tree.js disagree on ZERO");
    }

    function test_PoseidonMatchesCircomlib() public view {
        // poseidon(1, 2) as computed by circomlib, circomlibjs and poseidon-lite alike.
        assertEq(
            hasher.poseidon([uint256(1), uint256(2)]),
            7853200120776062878684798364095072458815029376092732009249414926327459813530
        );
    }

    /* ------------------------------------------------------------------- enrolment */

    function test_AHolderCanEnrolOnce() public {
        vm.prank(alice);
        uint32 index = lab.enrol(aliceCert, 111);
        assertEq(index, 0);
        assertEq(lab.memberCount(), 1);
        assertTrue(lab.certificateEnrolled(aliceCert));
    }

    function test_OneCertificateIsOneMembership() public {
        vm.prank(alice);
        lab.enrol(aliceCert, 111);

        vm.prank(alice);
        vm.expectRevert(PrivacyLab.AlreadyEnrolled.selector);
        lab.enrol(aliceCert, 222);
    }

    function test_SomebodyElsesCertificateIsNotYours() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(PrivacyLab.NotTheHolder.selector, alice));
        lab.enrol(aliceCert, 111);
    }

    function test_ARevokedCertificateCannotEnrol() public {
        vm.prank(issuer);
        certs.revoke(aliceCert, "issued in error");

        vm.prank(alice);
        vm.expectRevert(PrivacyLab.CertificateNotValid.selector);
        lab.enrol(aliceCert, 111);
    }

    function test_TwoPeopleCannotShareACommitment() public {
        vm.prank(alice);
        lab.enrol(aliceCert, 111);

        vm.prank(bob);
        vm.expectRevert(PrivacyLab.CommitmentAlreadyUsed.selector);
        lab.enrol(bobCert, 111);
    }

    function test_ACommitmentMustFitInTheField() public {
        vm.prank(alice);
        vm.expectRevert(PrivacyLab.NotInField.selector);
        lab.enrol(aliceCert, type(uint256).max);
    }

    function test_EnrolmentMovesTheRoot() public {
        uint256 before = lab.currentRoot();
        vm.prank(alice);
        lab.enrol(aliceCert, 111);
        assertTrue(lab.currentRoot() != before, "root did not change");
        assertTrue(lab.isKnownRoot(before), "the previous root should stay valid");
    }

    function test_EnrolmentStampsThePassport() public {
        // Read the role BEFORE pranking. A view call in the argument list is still an
        // external call and it consumes the prank. Fifth time in this repository.
        bytes32 stamper = passport.STAMPER_ROLE();
        vm.prank(admin);
        passport.grantRole(stamper, address(lab));
        vm.prank(alice);
        passport.mint();

        vm.prank(alice);
        lab.enrol(aliceCert, 111);
        assertTrue(passport.hasStamp(alice, 16), "no stamp");
    }

    /* --------------------------------------------------------------------- posting */

    function _enrolAlice() internal {
        vm.prank(alice);
        lab.enrol(aliceCert, 111);
    }

    function test_AnyoneCanCarryTheProof() public {
        _enrolAlice();
        // The point of the module: the post is sent by an address with no certificate and
        // no enrolment. Nothing in the record ties it to Alice.
        vm.prank(stranger);
        lab.postAnonymously(pA, pB, pC, lab.currentRoot(), 999, 1, "the water is off on Mill Lane");
    }

    function test_ANullifierWorksOnce() public {
        _enrolAlice();
        // Hoisted for the same reason as above, and then some: `vm.expectRevert` also
        // applies to the NEXT call, and `lab.currentRoot()` sitting in the argument list is
        // that next call. It does not revert, so the cheatcode fails with "next call did
        // not revert as expected" while pointing at the line you believe is under test.
        // The prank trap and the expectRevert trap are the same mistake wearing two hats.
        uint256 root = lab.currentRoot();

        vm.prank(stranger);
        lab.postAnonymously(pA, pB, pC, root, 999, 1, "first");

        vm.prank(stranger);
        vm.expectRevert(PrivacyLab.NullifierAlreadyUsed.selector);
        lab.postAnonymously(pA, pB, pC, root, 999, 1, "second");
    }

    function test_AnUnknownRootIsRefused() public {
        _enrolAlice();
        vm.expectRevert(PrivacyLab.UnknownRoot.selector);
        lab.postAnonymously(pA, pB, pC, 12345, 999, 1, "hello");
    }

    function test_ARecentRootStaysValid() public {
        _enrolAlice();
        uint256 oldRoot = lab.currentRoot();

        vm.prank(bob);
        lab.enrol(bobCert, 222);

        // Bob enrolling must not invalidate a proof Alice had already built.
        vm.prank(stranger);
        lab.postAnonymously(pA, pB, pC, oldRoot, 999, 1, "built before bob joined");
    }

    function test_ARootFallsOutOfTheWindowEventually() public {
        _enrolAlice();
        uint256 oldRoot = lab.currentRoot();

        // ROOT_HISTORY more enrolments push it out. Each needs its own certificate, so mint
        // them as we go.
        for (uint256 i = 0; i < lab.ROOT_HISTORY(); i++) {
            address who = address(uint160(0x1000 + i));
            vm.prank(who);
            residents.register(keccak256(abi.encodePacked(i)));
            vm.prank(issuer);
            uint256 id = certs.issue(who, "CS 5590", keccak256(abi.encodePacked("doc", i)));
            vm.prank(who);
            lab.enrol(id, 1000 + i);
        }

        assertFalse(lab.isKnownRoot(oldRoot), "root should have aged out");
    }

    function test_ABadProofIsRefused() public {
        PrivacyLab strict = new PrivacyLab(hasher, certs, new AlwaysNo(), passport);
        vm.prank(alice);
        strict.enrol(aliceCert, 111);
        uint256 root = strict.currentRoot();

        vm.expectRevert(PrivacyLab.BadProof.selector);
        strict.postAnonymously(pA, pB, pC, root, 999, 1, "hello");
    }

    function test_TheMessageIsBoundToTheProof() public view {
        // Two different messages hash to two different signals, so a proof built for one
        // cannot be replayed with the other. This is the check the circuit enforces; here
        // we only assert the contract's half is deterministic and distinct.
        assertTrue(lab.hashSignal("a") != lab.hashSignal("b"));
        assertEq(lab.hashSignal("a"), uint256(keccak256("a")) >> 8);
        assertTrue(lab.hashSignal("a") < type(uint256).max >> 8 << 1, "signal must fit the field");
    }

    function test_AnEmptyOrOversizedNoticeIsRefused() public {
        _enrolAlice();
        uint256 root = lab.currentRoot();

        vm.expectRevert(PrivacyLab.EmptyNotice.selector);
        lab.postAnonymously(pA, pB, pC, root, 1, 1, "");

        string memory long = new string(281);
        vm.expectRevert(abi.encodeWithSelector(PrivacyLab.NoticeTooLong.selector, 281, 280));
        lab.postAnonymously(pA, pB, pC, root, 2, 1, long);
    }

    /* --------------------------------------------------------- the honest limitation */

    function test_TheAnonymitySetIsAsSmallAsItLooks() public {
        // Not a security property -- a statement of fact the guide spends a section on. With
        // one member, a "1 of N" proof is a "1 of 1" proof, and the mathematics cannot help.
        _enrolAlice();
        assertEq(lab.memberCount(), 1);

        vm.prank(bob);
        lab.enrol(bobCert, 222);
        assertEq(lab.memberCount(), 2);
    }
}
