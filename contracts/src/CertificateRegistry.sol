// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ResidentRegistry} from "./ResidentRegistry.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Certificate Registry  (module 7)
/// @notice Problem: a diploma is a PDF. Anyone can edit a PDF, and checking one means
///         emailing the college and hoping somebody answers.
/// @dev    The certificate document stays with the holder. On chain there is only its
///         hash plus who issued it, to whom, and whether it is still valid — which is
///         exactly what a verifier needs and nothing more.
///
///         Modelled on W3C Verifiable Credentials: the issuer signs, the holder keeps,
///         the verifier checks. Revocation is a status flag the issuer controls, in the
///         spirit of a status list.
contract CertificateRegistry is Stamping {
    uint16 public constant MODULE_ID = 7;

    struct Certificate {
        address issuer;
        address holder;
        uint64 issuedAt;
        uint64 revokedAt; // 0 = valid
        string course;
        bytes32 docHash; // keccak256 of the certificate document
    }

    ResidentRegistry public immutable residents;

    Certificate[] private _certs; // index + 1 == public id
    mapping(address => uint256[]) private _byHolder;
    mapping(address => uint256[]) private _byIssuer;
    mapping(bytes32 => uint256) public idOfDocument; // hash → id, for "check this file"

    event CertificateIssued(
        uint256 indexed id, address indexed issuer, address indexed holder, string course, bytes32 docHash
    );
    event CertificateRevoked(uint256 indexed id, address indexed issuer, string reason);

    error NotAResident();
    error NoSuchCertificate();
    error NotTheIssuer(address issuer);
    error AlreadyRevoked();
    error SelfIssue();
    error EmptyDocHash();
    error DocumentAlreadyRegistered(uint256 id);

    constructor(ResidentRegistry residents_, TrustvillePassport passport_) Stamping(passport_) {
        residents = residents_;
    }

    /// Issue a certificate to someone else. Any resident may issue — so a verifier must
    /// always ask WHO signed it, never just "is it on the chain?". That is the lesson.
    function issue(address holder, string calldata course, bytes32 docHash) external returns (uint256 id) {
        if (!residents.isResident(msg.sender)) revert NotAResident();
        if (holder == msg.sender) revert SelfIssue();
        if (docHash == bytes32(0)) revert EmptyDocHash();
        if (idOfDocument[docHash] != 0) revert DocumentAlreadyRegistered(idOfDocument[docHash]);

        _certs.push(
            Certificate({
                issuer: msg.sender,
                holder: holder,
                issuedAt: uint64(block.timestamp),
                revokedAt: 0,
                course: course,
                docHash: docHash
            })
        );
        id = _certs.length;
        _byHolder[holder].push(id);
        _byIssuer[msg.sender].push(id);
        idOfDocument[docHash] = id;

        emit CertificateIssued(id, msg.sender, holder, course, docHash);
        _stamp(msg.sender, MODULE_ID);
    }

    /// Only the issuer can revoke, and revocation never deletes: the record stays, with a
    /// date. A verifier can still answer "was this valid last March?".
    function revoke(uint256 id, string calldata reason) external {
        Certificate storage c = _at(id);
        if (c.issuer != msg.sender) revert NotTheIssuer(c.issuer);
        if (c.revokedAt != 0) revert AlreadyRevoked();

        c.revokedAt = uint64(block.timestamp);
        emit CertificateRevoked(id, msg.sender, reason);
    }

    /// What a verifier actually calls: hand it the document hash, get back the facts.
    function verifyDocument(bytes32 docHash)
        external
        view
        returns (bool known, bool valid, address issuer, address holder, string memory course)
    {
        uint256 id = idOfDocument[docHash];
        if (id == 0) return (false, false, address(0), address(0), "");
        Certificate storage c = _certs[id - 1];
        return (true, c.revokedAt == 0, c.issuer, c.holder, c.course);
    }

    function isValid(uint256 id) external view returns (bool) {
        return _at(id).revokedAt == 0;
    }

    function count() external view returns (uint256) {
        return _certs.length;
    }

    function get(uint256 id) external view returns (Certificate memory) {
        return _at(id);
    }

    function certificatesOf(address holder) external view returns (uint256[] memory) {
        return _byHolder[holder];
    }

    function issuedBy(address issuer) external view returns (uint256[] memory) {
        return _byIssuer[issuer];
    }

    function _at(uint256 id) internal view returns (Certificate storage) {
        if (id == 0 || id > _certs.length) revert NoSuchCertificate();
        return _certs[id - 1];
    }
}
