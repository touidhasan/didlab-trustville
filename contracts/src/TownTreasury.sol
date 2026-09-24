// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Treasury  (module 11) — an M-of-N multisig
/// @notice Problem: public money spent on one person's say-so. A single signer is a single
///         point of both failure and temptation.
/// @dev    Nothing happens until M of N owners have confirmed the same transaction. The
///         contract holds the funds and performs the call itself, so no owner ever takes
///         custody in between.
///
///         Compare with the DAO next door (module 12). A multisig is fast, private about
///         *why*, and trusts a small named group. A DAO is slow, public, and trusts a token
///         distribution. Neither is strictly better — the question is who should be able to
///         stop a payment.
contract TownTreasury is Stamping {
    uint16 public constant MODULE_ID = 11;

    struct Payment {
        address to;
        uint256 value; // native TRUST sent with the call
        bytes data; // contract call, e.g. an ERC-20 transfer
        string memo;
        uint32 confirmations;
        bool executed;
    }

    address[] private _owners;
    mapping(address => bool) public isOwner;
    uint256 public threshold;

    Payment[] private _payments; // index + 1 == public id
    mapping(uint256 => mapping(address => bool)) public confirmedBy;

    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event ThresholdChanged(uint256 threshold);
    event PaymentProposed(uint256 indexed id, address indexed proposer, address indexed to, uint256 value, string memo);
    event PaymentConfirmed(uint256 indexed id, address indexed owner, uint32 confirmations);
    event ConfirmationRevoked(uint256 indexed id, address indexed owner, uint32 confirmations);
    event PaymentExecuted(uint256 indexed id, address indexed to, bytes result);
    event Received(address indexed from, uint256 amount);

    error NotAnOwner();
    error NotTheTreasury();
    error NoSuchPayment();
    error AlreadyExecuted();
    error AlreadyConfirmed();
    error NotConfirmed();
    error NotEnoughConfirmations(uint32 have, uint256 need);
    error BadThreshold(uint256 threshold, uint256 owners);
    error AlreadyAnOwner();
    error CallFailed(bytes reason);

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotAnOwner();
        _;
    }

    /// Changing the owner set or the threshold must itself go through the multisig.
    modifier onlyTreasury() {
        if (msg.sender != address(this)) revert NotTheTreasury();
        _;
    }

    constructor(address[] memory owners_, uint256 threshold_, TrustvillePassport passport_) Stamping(passport_) {
        if (threshold_ == 0 || threshold_ > owners_.length) revert BadThreshold(threshold_, owners_.length);
        for (uint256 i; i < owners_.length; i++) {
            address o = owners_[i];
            if (isOwner[o]) revert AlreadyAnOwner();
            isOwner[o] = true;
            _owners.push(o);
            emit OwnerAdded(o);
        }
        threshold = threshold_;
        emit ThresholdChanged(threshold_);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function propose(address to, uint256 value, bytes calldata data, string calldata memo)
        external
        onlyOwner
        returns (uint256 id)
    {
        _payments.push(
            Payment({to: to, value: value, data: data, memo: memo, confirmations: 0, executed: false})
        );
        id = _payments.length;
        emit PaymentProposed(id, msg.sender, to, value, memo);
        _confirm(id, msg.sender); // proposing is confirming
    }

    function confirm(uint256 id) external onlyOwner {
        _confirm(id, msg.sender);
    }

    /// An owner can change their mind, but only before execution.
    function revokeConfirmation(uint256 id) external onlyOwner {
        Payment storage p = _at(id);
        if (p.executed) revert AlreadyExecuted();
        if (!confirmedBy[id][msg.sender]) revert NotConfirmed();

        confirmedBy[id][msg.sender] = false;
        p.confirmations--;
        emit ConfirmationRevoked(id, msg.sender, p.confirmations);
    }

    /// Anyone may push the button once enough owners have signed — the confirmations are
    /// the authority, not who sends the final transaction.
    function execute(uint256 id) external {
        Payment storage p = _at(id);
        if (p.executed) revert AlreadyExecuted();
        if (p.confirmations < threshold) revert NotEnoughConfirmations(p.confirmations, threshold);

        p.executed = true; // set before the call
        (bool ok, bytes memory result) = p.to.call{value: p.value}(p.data);
        if (!ok) revert CallFailed(result);

        emit PaymentExecuted(id, p.to, result);
        _stamp(msg.sender, MODULE_ID);
    }

    /* ------------------------------------------- owner management, by multisig only */

    function addOwner(address owner) external onlyTreasury {
        if (isOwner[owner]) revert AlreadyAnOwner();
        isOwner[owner] = true;
        _owners.push(owner);
        emit OwnerAdded(owner);
    }

    function removeOwner(address owner) external onlyTreasury {
        if (!isOwner[owner]) revert NotAnOwner();
        if (_owners.length - 1 < threshold) revert BadThreshold(threshold, _owners.length - 1);
        isOwner[owner] = false;
        for (uint256 i; i < _owners.length; i++) {
            if (_owners[i] == owner) {
                _owners[i] = _owners[_owners.length - 1];
                _owners.pop();
                break;
            }
        }
        emit OwnerRemoved(owner);
    }

    function setThreshold(uint256 threshold_) external onlyTreasury {
        if (threshold_ == 0 || threshold_ > _owners.length) revert BadThreshold(threshold_, _owners.length);
        threshold = threshold_;
        emit ThresholdChanged(threshold_);
    }

    /* --------------------------------------------------------------------- views */

    function owners() external view returns (address[] memory) {
        return _owners;
    }

    function ownerCount() external view returns (uint256) {
        return _owners.length;
    }

    function count() external view returns (uint256) {
        return _payments.length;
    }

    function get(uint256 id) external view returns (Payment memory) {
        return _at(id);
    }

    /// Helper so the UI can build an ERC-20 transfer without an ABI encoder.
    function encodeTransfer(address to, uint256 amount) external pure returns (bytes memory) {
        return abi.encodeWithSignature("transfer(address,uint256)", to, amount);
    }

    function _confirm(uint256 id, address owner) internal {
        Payment storage p = _at(id);
        if (p.executed) revert AlreadyExecuted();
        if (confirmedBy[id][owner]) revert AlreadyConfirmed();

        confirmedBy[id][owner] = true;
        p.confirmations++;
        emit PaymentConfirmed(id, owner, p.confirmations);
    }

    function _at(uint256 id) internal view returns (Payment storage) {
        if (id == 0 || id > _payments.length) revert NoSuchPayment();
        return _payments[id - 1];
    }
}
