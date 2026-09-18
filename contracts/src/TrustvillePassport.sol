// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ResidentRegistry} from "./ResidentRegistry.sol";

/// @title Trustville Passport  (module 2)
/// @notice A soulbound NFT: it proves *you* did something, so it must not be sellable.
/// @dev    ERC-721 with transfers disabled (ERC-5192 "locked"). Each completed module
///         adds a stamp. Metadata is generated on chain — no server, no IPFS pin to lose.
contract TrustvillePassport is ERC721, AccessControl {
    bytes32 public constant STAMPER_ROLE = keccak256("STAMPER_ROLE");

    /// ERC-5192 interface id, for wallets that check whether a token is locked.
    bytes4 private constant _ERC5192_ID = 0xb45a3c0e;

    ResidentRegistry public immutable registry;

    uint256 private _nextId = 1;
    mapping(address => uint256) public passportOf; // 0 = none
    mapping(uint256 => uint16[]) private _stamps; // tokenId => module ids, in order
    mapping(uint256 => mapping(uint16 => uint64)) public stampedAt; // tokenId => module => time

    event Locked(uint256 tokenId); // ERC-5192
    event PassportIssued(address indexed resident, uint256 indexed tokenId);
    event Stamped(uint256 indexed tokenId, uint16 indexed moduleId, address indexed by);

    error NotAResident();
    error AlreadyHasPassport();
    error NoPassport();
    error AlreadyStamped();
    error Soulbound();

    constructor(address admin, ResidentRegistry registry_) ERC721("Trustville Passport", "TVP") {
        registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Mint your own passport. Requires an active resident record.
    function mint() external returns (uint256 tokenId) {
        if (!registry.isResident(msg.sender)) revert NotAResident();
        if (passportOf[msg.sender] != 0) revert AlreadyHasPassport();

        tokenId = _nextId++;
        passportOf[msg.sender] = tokenId;
        _safeMint(msg.sender, tokenId);
        emit Locked(tokenId);
        emit PassportIssued(msg.sender, tokenId);

        _stamp(tokenId, 1); // module 1: you are a resident
        _stamp(tokenId, 2); // module 2: you hold a passport
    }

    /// @notice Add a module stamp. Held by module CONTRACTS, not by people.
    function stamp(address resident, uint16 moduleId) external onlyRole(STAMPER_ROLE) {
        uint256 tokenId = passportOf[resident];
        if (tokenId == 0) revert NoPassport();
        _stamp(tokenId, moduleId);
    }

    function stampsOf(address resident) external view returns (uint16[] memory) {
        return _stamps[passportOf[resident]];
    }

    function hasStamp(address resident, uint16 moduleId) external view returns (bool) {
        return stampedAt[passportOf[resident]][moduleId] != 0;
    }

    /// ERC-5192: every passport is locked, forever.
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 count = _stamps[tokenId].length;
        string memory json = string.concat(
            '{"name":"Trustville Passport #',
            Strings.toString(tokenId),
            '","description":"Soulbound record of modules completed in Trustville.",',
            '"attributes":[{"trait_type":"Stamps","value":',
            Strings.toString(count),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function supportsInterface(bytes4 id) public view override(ERC721, AccessControl) returns (bool) {
        return id == _ERC5192_ID || super.supportsInterface(id);
    }

    function _stamp(uint256 tokenId, uint16 moduleId) internal {
        if (stampedAt[tokenId][moduleId] != 0) revert AlreadyStamped();
        stampedAt[tokenId][moduleId] = uint64(block.timestamp);
        _stamps[tokenId].push(moduleId);
        emit Stamped(tokenId, moduleId, msg.sender);
    }

    /// Block every transfer; allow minting only. This is what "soulbound" means in code.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
