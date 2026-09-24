// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Wrapper} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Wrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title Trustville Vote  (vTVD) — voting power for the Council
/// @notice TVD is a plain ERC-20: it can be spent, but it cannot vote. Counting votes needs
///         balances as they stood at a past block, or anyone could buy tokens after a
///         proposal opens, vote, and sell.
/// @dev    Rather than redeploy TVD and invalidate every balance students hold, this wraps
///         it: deposit TVD, receive vTVD 1:1, withdraw whenever you like. vTVD is
///         ERC20Votes, so it keeps a checkpointed history of balances.
///
///         Two things students always trip over, and should:
///         1. **Wrapping is not voting power.** You must also `delegate` — to yourself if
///            you want to vote yourself. Undelegated tokens count for nobody. This catches
///            out real DAOs regularly.
///         2. **Voting power is measured at the proposal's snapshot block**, not now, which
///            is why buying tokens mid-vote does not help.
contract VoteToken is ERC20, ERC20Permit, ERC20Votes, ERC20Wrapper {
    constructor(IERC20 townToken)
        ERC20("Trustville Vote", "vTVD")
        ERC20Permit("Trustville Vote")
        ERC20Wrapper(townToken)
    {}

    /// Convenience: wrap and delegate to yourself in one transaction, because tokens that
    /// are wrapped but not delegated are a silent no-op at voting time.
    function depositAndSelfDelegate(uint256 amount) external {
        depositFor(msg.sender, amount);
        _delegate(msg.sender, msg.sender);
    }

    function decimals() public view override(ERC20, ERC20Wrapper) returns (uint8) {
        return super.decimals();
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
