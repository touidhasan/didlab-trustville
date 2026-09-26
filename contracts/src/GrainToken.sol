// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ResidentRegistry} from "./ResidentRegistry.sol";

/// @title Trustville Grain  (module 15) — the town's second asset
/// @notice One token is not a market. TVD is the currency; GRAIN is the thing farmers
///         actually sell, and the pair of them is what makes a price possible.
/// @dev    A price is a ratio between two things. Until now Trustville has had no ratio
///         to argue about: a TVD was worth a TVD. Introducing a second asset is what turns
///         the Bank stop into a market, and it is the smallest change that makes swapping,
///         lending and liquidation mean anything.
///
///         Getting some is rate-limited rather than gated: any resident may harvest a
///         fixed amount once per cooldown. That is the same rule the rest of the town
///         follows — anything students can call is open by design and limited by the
///         contract, so a griefer costs the class nothing but their own gas.
///
///         Note what this deliberately is NOT: there is no human minter. `harvest` is the
///         only way GRAIN comes into existence, and its rules are the same for everybody,
///         including the town admin.
contract GrainToken is ERC20, AccessControl {
    uint256 public constant HARVEST_AMOUNT = 100 ether;
    uint64 public constant MIN_COOLDOWN = 1 minutes;
    uint64 public constant MAX_COOLDOWN = 7 days;

    ResidentRegistry public immutable registry;

    uint64 public cooldown;
    mapping(address => uint64) public lastHarvest;

    event Harvested(address indexed farmer, uint256 amount, uint64 nextAllowed);
    event CooldownChanged(uint64 cooldown);

    error NotAResident();
    error TooSoon(uint64 allowedAt);
    error BadCooldown();

    constructor(address admin, ResidentRegistry registry_, uint64 cooldown_)
        ERC20("Trustville Grain", "GRAIN")
    {
        if (cooldown_ < MIN_COOLDOWN || cooldown_ > MAX_COOLDOWN) revert BadCooldown();
        registry = registry_;
        cooldown = cooldown_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// Bring in the harvest. Once per cooldown, same amount for everyone.
    function harvest() external {
        if (!registry.isResident(msg.sender)) revert NotAResident();

        uint64 last = lastHarvest[msg.sender];
        uint64 allowedAt = last == 0 ? 0 : last + cooldown;
        if (last != 0 && block.timestamp < allowedAt) revert TooSoon(allowedAt);

        lastHarvest[msg.sender] = uint64(block.timestamp);
        _mint(msg.sender, HARVEST_AMOUNT);
        emit Harvested(msg.sender, HARVEST_AMOUNT, uint64(block.timestamp) + cooldown);
    }

    function harvestableAt(address who) external view returns (uint64) {
        uint64 last = lastHarvest[who];
        return last == 0 ? 0 : last + cooldown;
    }

    /// Anyone may burn their own — useful when a class wants to watch supply move.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function setCooldown(uint64 cooldown_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (cooldown_ < MIN_COOLDOWN || cooldown_ > MAX_COOLDOWN) revert BadCooldown();
        cooldown = cooldown_;
        emit CooldownChanged(cooldown_);
    }
}
