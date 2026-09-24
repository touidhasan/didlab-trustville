// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Stamping — shared passport-stamping helper for module contracts
/// @dev   A module should never break because stamping is unavailable, but it must not
///        swallow failures either.
///
///        The obvious implementation, `try passport.stamp(...) {} catch {}`, is a trap.
///        A caught failure still "succeeds", so eth_estimateGas binary-searches down to
///        the cheapest limit where the transaction succeeds — the one where the inner
///        call runs out of gas and is caught. The result: every transaction silently
///        skips the stamp, and nothing looks wrong. We hit exactly this in testing.
///
///        So instead of catching failures, check the preconditions first. All three
///        checks are view calls, so gas estimation sees the real cost of the stamp.
abstract contract Stamping {
    TrustvillePassport public immutable passport;

    constructor(TrustvillePassport passport_) {
        passport = passport_;
    }

    function _stamp(address who, uint16 moduleId) internal {
        if (address(passport) == address(0)) return; // stamping not configured
        if (passport.passportOf(who) == 0) return; // they never minted one
        if (passport.hasStamp(who, moduleId)) return; // already earned it
        if (!passport.hasRole(passport.STAMPER_ROLE(), address(this))) return; // admin has not granted the role
        passport.stamp(who, moduleId);
    }
}
