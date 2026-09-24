// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ResidentRegistry} from "./ResidentRegistry.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Product Registry  (module 4)
/// @notice Problem: "is this honey really from the farm it claims?" Paper trails are easy
///         to forge and easy to lose.
/// @dev    Each product carries a custody chain: who made it, who holds it now, and every
///         handoff in between. The full document stays off chain; only its hash is stored,
///         so a certificate can be proven unaltered without publishing it.
///
///         This is the TEXTBOOK version, deliberately: an open registry where anyone may
///         claim any origin. The honest limitation is the lesson — a chain proves the
///         RECORD has not changed, not that the claim was true when it was written.
contract ProductRegistry is Stamping {
    uint16 public constant MODULE_ID = 4;

    struct Product {
        address creator;
        address holder;
        uint64 createdAt;
        uint32 transfers;
        string name;
        string origin;
        bytes32 docHash; // hash of the off-chain certificate, 0 if none
    }

    ResidentRegistry public immutable residents;

    Product[] private _products; // index + 1 == public id

    event ProductRegistered(
        uint256 indexed id, address indexed creator, string name, string origin, bytes32 docHash
    );
    event CustodyTransferred(uint256 indexed id, address indexed from, address indexed to, string note);

    error NotAResident();
    error NoSuchProduct();
    error NotTheHolder(address holder);
    error SameHolder();

    constructor(ResidentRegistry residents_, TrustvillePassport passport_) Stamping(passport_) {
        residents = residents_;
    }

    function register(string calldata name, string calldata origin, bytes32 docHash)
        external
        returns (uint256 id)
    {
        if (!residents.isResident(msg.sender)) revert NotAResident();

        _products.push(
            Product({
                creator: msg.sender,
                holder: msg.sender,
                createdAt: uint64(block.timestamp),
                transfers: 0,
                name: name,
                origin: origin,
                docHash: docHash
            })
        );
        id = _products.length;
        emit ProductRegistered(id, msg.sender, name, origin, docHash);
        _stamp(msg.sender, MODULE_ID);
    }

    function transferCustody(uint256 id, address to, string calldata note) external {
        Product storage p = _at(id);
        if (p.holder != msg.sender) revert NotTheHolder(p.holder);
        if (to == msg.sender) revert SameHolder();

        p.holder = to;
        unchecked {
            p.transfers++;
        }
        emit CustodyTransferred(id, msg.sender, to, note);
    }

    function count() external view returns (uint256) {
        return _products.length;
    }

    function get(uint256 id) external view returns (Product memory) {
        return _at(id);
    }

    function _at(uint256 id) internal view returns (Product storage) {
        if (id == 0 || id > _products.length) revert NoSuchProduct();
        return _products[id - 1];
    }
}
