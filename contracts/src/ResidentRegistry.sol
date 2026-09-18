// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title Trustville Resident Registry  (module 1)
/// @notice Problem: proving you belong to the town without a central database anyone
///         can quietly edit.
/// @dev    The credential itself (a W3C Verifiable Credential) stays OFF chain with the
///         resident. Only its hash is stored here, so the chain proves *that* a credential
///         exists and has not changed, without ever holding personal data.
contract ResidentRegistry is AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

    struct Resident {
        uint64 since; // 0 = never registered
        uint64 revokedAt; // 0 = active
        bytes32 credentialHash; // hash of the off-chain credential
    }

    mapping(address => Resident) private _residents;
    uint256 public residentCount;

    /// Students register themselves while this is true; the admin can close it after a term.
    bool public openRegistration = true;

    event ResidentRegistered(address indexed resident, bytes32 credentialHash, address registeredBy);
    event ResidentRevoked(address indexed resident, address revokedBy);
    event RegistrationOpened(bool open);

    error AlreadyRegistered();
    error RegistrationClosed();
    error NotRegistered();
    error AlreadyRevoked();

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(REGISTRAR_ROLE, admin);
    }

    /// @notice Register yourself. `credentialHash` is keccak256 of your credential document.
    function register(bytes32 credentialHash) external {
        if (!openRegistration) revert RegistrationClosed();
        _register(msg.sender, credentialHash);
    }

    /// @notice Register someone else — for students without a working wallet yet.
    function registerFor(address resident, bytes32 credentialHash) external onlyRole(REGISTRAR_ROLE) {
        _register(resident, credentialHash);
    }

    function revoke(address resident) external onlyRole(REGISTRAR_ROLE) {
        Resident storage r = _residents[resident];
        if (r.since == 0) revert NotRegistered();
        if (r.revokedAt != 0) revert AlreadyRevoked();
        r.revokedAt = uint64(block.timestamp);
        emit ResidentRevoked(resident, msg.sender);
    }

    function setOpenRegistration(bool open) external onlyRole(DEFAULT_ADMIN_ROLE) {
        openRegistration = open;
        emit RegistrationOpened(open);
    }

    function isResident(address who) public view returns (bool) {
        Resident storage r = _residents[who];
        return r.since != 0 && r.revokedAt == 0;
    }

    function residentOf(address who) external view returns (Resident memory) {
        return _residents[who];
    }

    function _register(address resident, bytes32 credentialHash) internal {
        if (_residents[resident].since != 0) revert AlreadyRegistered();
        _residents[resident] =
            Resident({since: uint64(block.timestamp), revokedAt: 0, credentialHash: credentialHash});
        unchecked {
            residentCount++;
        }
        emit ResidentRegistered(resident, credentialHash, msg.sender);
    }
}
