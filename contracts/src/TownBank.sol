// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ResidentRegistry} from "./ResidentRegistry.sol";
import {TownToken} from "./TownToken.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Bank  (module 3)
/// @notice Hands every resident one welcome grant of TVD, once.
/// @dev    This contract — not a person — holds MINTER_ROLE on the token and STAMPER_ROLE
///         on the passport. The rule "one grant per resident" is enforced by code, so no
///         operator has to be trusted to apply it fairly.
contract TownBank is AccessControl {
    ResidentRegistry public immutable registry;
    TownToken public immutable token;
    TrustvillePassport public immutable passport;

    uint16 public constant MODULE_TOKEN = 3;

    uint256 public grantAmount;
    mapping(address => bool) public hasClaimed;
    uint256 public grantsIssued;

    event WelcomeGrantClaimed(address indexed resident, uint256 amount);
    event GrantAmountChanged(uint256 amount, address changedBy);

    error NotAResident();
    error AlreadyClaimed();

    constructor(
        address admin,
        ResidentRegistry registry_,
        TownToken token_,
        TrustvillePassport passport_,
        uint256 grantAmount_
    ) {
        registry = registry_;
        token = token_;
        passport = passport_;
        grantAmount = grantAmount_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function claimWelcomeGrant() external {
        if (!registry.isResident(msg.sender)) revert NotAResident();
        if (hasClaimed[msg.sender]) revert AlreadyClaimed();

        hasClaimed[msg.sender] = true; // set before external calls
        unchecked {
            grantsIssued++;
        }

        token.mint(msg.sender, grantAmount);
        if (passport.passportOf(msg.sender) != 0 && !passport.hasStamp(msg.sender, MODULE_TOKEN)) {
            passport.stamp(msg.sender, MODULE_TOKEN);
        }
        emit WelcomeGrantClaimed(msg.sender, grantAmount);
    }

    function setGrantAmount(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantAmount = amount;
        emit GrantAmountChanged(amount, msg.sender);
    }
}
