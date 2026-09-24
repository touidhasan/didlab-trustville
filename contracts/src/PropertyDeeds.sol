// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ResidentRegistry} from "./ResidentRegistry.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Property Deeds  (module 9)
/// @notice Problem: deed fraud. Paper titles are forged, registries are edited, and in many
///         places nobody can say with certainty who owns a house.
/// @dev    A deed is an ERC-721 token — and this is the module where that standard finally
///         means what it says. Compare it with the Passport (module 2), which is the same
///         standard with transfers disabled: a passport must NOT be sellable, a deed must be.
///         Same interface, opposite requirement.
///
///         Registration is open, so a deed is only a CLAIM until the town certifies it.
///         Certification is a role, and it is deliberately cleared on transfer: the town
///         vouches for a specific owner, not for a token forever.
contract PropertyDeeds is ERC721, AccessControl, Stamping {
    bytes32 public constant CERTIFIER_ROLE = keccak256("CERTIFIER_ROLE");
    uint16 public constant MODULE_ID = 9;

    struct Property {
        address registrant;
        uint64 registeredAt;
        bool certified;
        string addressLine;
        bytes32 docHash; // hash of the off-chain title document
    }

    ResidentRegistry public immutable residents;

    uint256 private _nextId = 1;
    mapping(uint256 => Property) private _props;

    event PropertyRegistered(uint256 indexed id, address indexed registrant, string addressLine, bytes32 docHash);
    event PropertyCertified(uint256 indexed id, address indexed by, address indexed owner);
    event CertificationCleared(uint256 indexed id, address indexed previousOwner);

    error NotAResident();
    error NoSuchProperty();
    error EmptyAddressLine();

    constructor(address admin, ResidentRegistry residents_, TrustvillePassport passport_)
        ERC721("Trustville Property Deed", "TVD-DEED")
        Stamping(passport_)
    {
        residents = residents_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(CERTIFIER_ROLE, admin);
    }

    function register(string calldata addressLine, bytes32 docHash) external returns (uint256 id) {
        if (!residents.isResident(msg.sender)) revert NotAResident();
        if (bytes(addressLine).length == 0) revert EmptyAddressLine();

        id = _nextId++;
        _props[id] = Property({
            registrant: msg.sender,
            registeredAt: uint64(block.timestamp),
            certified: false,
            addressLine: addressLine,
            docHash: docHash
        });
        _safeMint(msg.sender, id);

        emit PropertyRegistered(id, msg.sender, addressLine, docHash);
        _stamp(msg.sender, MODULE_ID);
    }

    /// The town vouches that this owner really holds this property.
    function certify(uint256 id) external onlyRole(CERTIFIER_ROLE) {
        Property storage p = _get(id);
        p.certified = true;
        emit PropertyCertified(id, msg.sender, ownerOf(id));
    }

    function get(uint256 id) external view returns (Property memory) {
        return _get(id);
    }

    function count() external view returns (uint256) {
        return _nextId - 1;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        Property storage p = _props[id];
        string memory json = string.concat(
            '{"name":"Deed #',
            Strings.toString(id),
            '","description":"',
            p.addressLine,
            '","attributes":[{"trait_type":"Certified","value":"',
            p.certified ? "yes" : "no",
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function supportsInterface(bytes4 id) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(id);
    }

    /// A deed transfers like any NFT — but certification does not travel with it.
    function _update(address to, uint256 id, address auth) internal override returns (address) {
        address from = super._update(to, id, auth);
        if (from != address(0) && to != address(0) && _props[id].certified) {
            _props[id].certified = false;
            emit CertificationCleared(id, from);
        }
        return from;
    }

    function _get(uint256 id) internal view returns (Property storage) {
        if (id == 0 || id >= _nextId) revert NoSuchProperty();
        return _props[id];
    }
}
