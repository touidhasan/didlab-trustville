// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Trustville Dollar  (module 3)
/// @notice The town's local currency: an ordinary ERC-20, so every wallet and exchange
///         already knows how to handle it.
/// @dev    Minting is a role, and that role is held by the Bank CONTRACT — no human can
///         print money. TRUST (the chain's native coin) pays gas; TVD is the town currency.
contract TownToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 public immutable maxSupply;

    error MaxSupplyExceeded(uint256 requested, uint256 remaining);

    constructor(address admin, uint256 maxSupply_) ERC20("Trustville Dollar", "TVD") {
        maxSupply = maxSupply_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        uint256 remaining = maxSupply - totalSupply();
        if (amount > remaining) revert MaxSupplyExceeded(amount, remaining);
        _mint(to, amount);
    }

    /// Anyone may burn their own tokens — useful when students test supply changes.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
