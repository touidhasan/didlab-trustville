// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Rent Escrow  (module 10)
/// @notice Problem: the security deposit. The landlord holds the tenant's money and decides
///         alone whether to give it back — the tenant's only recourse is a court.
/// @dev    The deposit sits in the contract for the whole lease. When the lease ends the
///         landlord has a fixed window to claim against it, in public, with a reason. If no
///         claim arrives, the tenant simply takes the money back — no permission needed,
///         which is the part a paper tenancy cannot offer.
///
///         Rent itself is NOT escrowed: it goes straight to the landlord. Escrowing money
///         that is definitely owed would only add risk. Escrow the disputed thing, not
///         everything.
contract RentEscrow is AccessControl, Stamping {
    using SafeERC20 for IERC20;

    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    uint16 public constant MODULE_ID = 10;

    // Bounds, not fixed values: an instructor can run a 5-minute lease in a lab and a
    // week-long one for homework, and students must reason about what the numbers mean.
    uint64 public constant MIN_TERM = 5 minutes;
    uint64 public constant MAX_TERM = 365 days;
    uint64 public constant MIN_CLAIM_WINDOW = 2 minutes;
    uint64 public constant MAX_CLAIM_WINDOW = 30 days;

    enum State {
        None,
        Offered,
        Active,
        Claimed,
        Settled
    }

    struct Lease {
        address landlord;
        address tenant;
        uint256 deedId;
        uint256 rent;
        uint256 deposit;
        uint256 claimAmount;
        uint64 endsAt;
        uint64 claimWindow;
        uint32 rentPaid; // number of payments made
        State state;
        string claimReason;
    }

    IERC20 public immutable token;
    IERC721 public immutable deeds;

    Lease[] private _leases; // index + 1 == public id
    mapping(address => uint256[]) private _byParty;

    event LeaseOffered(uint256 indexed id, address indexed landlord, address indexed tenant, uint256 rent, uint256 deposit, uint64 endsAt);
    event LeaseAccepted(uint256 indexed id, address indexed tenant, uint256 deposit);
    event RentPaid(uint256 indexed id, address indexed tenant, uint256 amount, uint32 paymentNumber);
    event DepositClaimed(uint256 indexed id, address indexed landlord, uint256 amount, string reason);
    event DepositReturned(uint256 indexed id, address indexed tenant, uint256 amount);
    event ClaimResolved(uint256 indexed id, address indexed arbiter, uint256 toLandlord, uint256 toTenant);

    error NotTheDeedOwner(address owner);
    error NoSuchLease();
    error NotTheTenant();
    error NotTheLandlord();
    error WrongState(State state);
    error TermOutOfRange(uint64 min, uint64 max);
    error ClaimWindowOutOfRange(uint64 min, uint64 max);
    error TenantIsLandlord();
    error LeaseNotEnded(uint64 endsAt);
    error LeaseEnded();
    error ClaimWindowOpen(uint64 until);
    error ClaimWindowClosed(uint64 until);
    error ClaimTooLarge(uint256 deposit);

    constructor(address admin, IERC20 token_, IERC721 deeds_, TrustvillePassport passport_)
        Stamping(passport_)
    {
        token = token_;
        deeds = deeds_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin);
    }

    /// The landlord must hold the deed for the property being let.
    function offerLease(
        uint256 deedId,
        address tenant,
        uint256 rent,
        uint256 deposit,
        uint64 term,
        uint64 claimWindow
    ) external returns (uint256 id) {
        address owner = deeds.ownerOf(deedId);
        if (owner != msg.sender) revert NotTheDeedOwner(owner);
        if (tenant == msg.sender) revert TenantIsLandlord();
        if (term < MIN_TERM || term > MAX_TERM) revert TermOutOfRange(MIN_TERM, MAX_TERM);
        if (claimWindow < MIN_CLAIM_WINDOW || claimWindow > MAX_CLAIM_WINDOW) {
            revert ClaimWindowOutOfRange(MIN_CLAIM_WINDOW, MAX_CLAIM_WINDOW);
        }

        _leases.push(
            Lease({
                landlord: msg.sender,
                tenant: tenant,
                deedId: deedId,
                rent: rent,
                deposit: deposit,
                claimAmount: 0,
                endsAt: uint64(block.timestamp) + term,
                claimWindow: claimWindow,
                rentPaid: 0,
                state: State.Offered,
                claimReason: ""
            })
        );
        id = _leases.length;
        _byParty[msg.sender].push(id);
        _byParty[tenant].push(id);
        emit LeaseOffered(id, msg.sender, tenant, rent, deposit, _leases[id - 1].endsAt);
    }

    /// Tenant accepts and the deposit moves into the contract — not to the landlord.
    function acceptLease(uint256 id) external {
        Lease storage l = _at(id);
        if (msg.sender != l.tenant) revert NotTheTenant();
        if (l.state != State.Offered) revert WrongState(l.state);

        l.state = State.Active;
        if (l.deposit > 0) token.safeTransferFrom(msg.sender, address(this), l.deposit);

        emit LeaseAccepted(id, msg.sender, l.deposit);
        _stamp(msg.sender, MODULE_ID);
    }

    /// Rent goes straight to the landlord: it is owed, so there is nothing to hold.
    function payRent(uint256 id) external {
        Lease storage l = _at(id);
        if (msg.sender != l.tenant) revert NotTheTenant();
        if (l.state != State.Active) revert WrongState(l.state);
        if (block.timestamp >= l.endsAt) revert LeaseEnded();

        unchecked {
            l.rentPaid++;
        }
        if (l.rent > 0) token.safeTransferFrom(msg.sender, l.landlord, l.rent);
        emit RentPaid(id, msg.sender, l.rent, l.rentPaid);
    }

    /// After the lease ends the landlord has CLAIM_WINDOW to claim part of the deposit,
    /// in public and with a stated reason.
    function claimDeposit(uint256 id, uint256 amount, string calldata reason) external {
        Lease storage l = _at(id);
        if (msg.sender != l.landlord) revert NotTheLandlord();
        if (l.state != State.Active) revert WrongState(l.state);
        if (block.timestamp < l.endsAt) revert LeaseNotEnded(l.endsAt);
        if (block.timestamp >= l.endsAt + l.claimWindow) revert ClaimWindowClosed(l.endsAt + l.claimWindow);
        if (amount > l.deposit) revert ClaimTooLarge(l.deposit);

        l.state = State.Claimed;
        l.claimAmount = amount;
        l.claimReason = reason;
        emit DepositClaimed(id, msg.sender, amount, reason);
    }

    /// No claim in the window: the tenant takes the deposit back. Nobody has to agree.
    function returnDeposit(uint256 id) external {
        Lease storage l = _at(id);
        if (msg.sender != l.tenant) revert NotTheTenant();
        if (l.state != State.Active) revert WrongState(l.state);
        uint64 until = l.endsAt + l.claimWindow;
        if (block.timestamp < until) revert ClaimWindowOpen(until);

        l.state = State.Settled;
        uint256 amount = l.deposit;
        if (amount > 0) token.safeTransfer(l.tenant, amount);
        emit DepositReturned(id, l.tenant, amount);
    }

    /// A claim is a dispute, so a human decides — the same honest limit as module 5.
    function resolveClaim(uint256 id, uint256 toLandlord) external onlyRole(ARBITER_ROLE) {
        Lease storage l = _at(id);
        if (l.state != State.Claimed) revert WrongState(l.state);
        if (toLandlord > l.deposit) revert ClaimTooLarge(l.deposit);

        l.state = State.Settled;
        uint256 toTenant = l.deposit - toLandlord;
        if (toLandlord > 0) token.safeTransfer(l.landlord, toLandlord);
        if (toTenant > 0) token.safeTransfer(l.tenant, toTenant);
        emit ClaimResolved(id, msg.sender, toLandlord, toTenant);
    }

    function count() external view returns (uint256) {
        return _leases.length;
    }

    function get(uint256 id) external view returns (Lease memory) {
        return _at(id);
    }

    function leasesOf(address party) external view returns (uint256[] memory) {
        return _byParty[party];
    }

    function _at(uint256 id) internal view returns (Lease storage) {
        if (id == 0 || id > _leases.length) revert NoSuchLease();
        return _leases[id - 1];
    }
}
