// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ResidentRegistry} from "./ResidentRegistry.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Event Tickets  (module 8)
/// @notice Problem: forged tickets, and a seller who takes the money for an event that
///         never happens.
/// @dev    ERC-1155 is the right shape here: one token id per event, many identical
///         tickets inside it. ERC-721 would mean a separate token for every seat, and
///         ERC-20 could not tell one event from another.
///
///         Money is held by the contract until the event starts, so a cancelled event
///         can refund. That reuses the escrow idea from module 5 — the same pattern
///         shows up wherever one side pays before the other delivers.
contract EventTickets is ERC1155, Stamping {
    using SafeERC20 for IERC20;

    uint16 public constant MODULE_ID = 8;

    struct EventInfo {
        address organiser;
        uint256 price; // TVD per ticket
        uint64 startsAt;
        uint32 capacity;
        uint32 sold;
        uint32 redeemed;
        bool cancelled;
        bool withdrawn;
        string name;
    }

    IERC20 public immutable token;
    ResidentRegistry public immutable residents;

    EventInfo[] private _events; // index + 1 == token id
    mapping(uint256 => mapping(address => uint256)) public paidBy; // refundable amount

    event EventCreated(uint256 indexed id, address indexed organiser, string name, uint256 price, uint32 capacity);
    event TicketsBought(uint256 indexed id, address indexed buyer, uint256 quantity, uint256 paid);
    event TicketsRedeemed(uint256 indexed id, address indexed holder, uint256 quantity);
    event EventCancelled(uint256 indexed id);
    event Refunded(uint256 indexed id, address indexed buyer, uint256 amount);
    event ProceedsWithdrawn(uint256 indexed id, address indexed organiser, uint256 amount);

    error NotAResident();
    error NoSuchEvent();
    error NotTheOrganiser(address organiser);
    error BadCapacity();
    error BadStart();
    error SoldOut(uint32 remaining);
    error EventCancelledError();
    error EventStarted();
    error EventNotStarted();
    error NotCancelled();
    error NothingToRefund();
    error AlreadyWithdrawn();
    error NotEnoughTickets();
    error ZeroQuantity();

    constructor(IERC20 token_, ResidentRegistry residents_, TrustvillePassport passport_)
        ERC1155("")
        Stamping(passport_)
    {
        token = token_;
        residents = residents_;
    }

    function createEvent(string calldata name, uint256 price, uint32 capacity, uint64 startsAt)
        external
        returns (uint256 id)
    {
        if (!residents.isResident(msg.sender)) revert NotAResident();
        if (capacity == 0 || capacity > 100_000) revert BadCapacity();
        if (startsAt <= block.timestamp) revert BadStart();

        _events.push(
            EventInfo({
                organiser: msg.sender,
                price: price,
                startsAt: startsAt,
                capacity: capacity,
                sold: 0,
                redeemed: 0,
                cancelled: false,
                withdrawn: false,
                name: name
            })
        );
        id = _events.length;
        emit EventCreated(id, msg.sender, name, price, capacity);
    }

    /// Buy tickets. Requires an ERC-20 approval for price × quantity.
    function buy(uint256 id, uint32 quantity) external {
        EventInfo storage e = _at(id);
        if (quantity == 0) revert ZeroQuantity();
        if (e.cancelled) revert EventCancelledError();
        if (block.timestamp >= e.startsAt) revert EventStarted();
        uint32 remaining = e.capacity - e.sold;
        if (quantity > remaining) revert SoldOut(remaining);

        uint256 cost = e.price * quantity;
        e.sold += quantity;
        paidBy[id][msg.sender] += cost;

        if (cost > 0) token.safeTransferFrom(msg.sender, address(this), cost);
        _mint(msg.sender, id, quantity, "");

        emit TicketsBought(id, msg.sender, quantity, cost);
        _stamp(msg.sender, MODULE_ID);
    }

    /// Redeem at the door: the ticket is burned, so it cannot be used twice or resold
    /// after entry.
    function redeem(uint256 id, uint32 quantity) external {
        EventInfo storage e = _at(id);
        if (quantity == 0) revert ZeroQuantity();
        if (e.cancelled) revert EventCancelledError();
        if (balanceOf(msg.sender, id) < quantity) revert NotEnoughTickets();

        e.redeemed += quantity;
        _burn(msg.sender, id, quantity);
        emit TicketsRedeemed(id, msg.sender, quantity);
    }

    /// Before the event only. Afterwards the organiser has already earned the money.
    function cancel(uint256 id) external {
        EventInfo storage e = _at(id);
        if (e.organiser != msg.sender) revert NotTheOrganiser(e.organiser);
        if (block.timestamp >= e.startsAt) revert EventStarted();
        if (e.cancelled) revert EventCancelledError();

        e.cancelled = true;
        emit EventCancelled(id);
    }

    /// Cancelled event: hand the tickets back, take the money back.
    function refund(uint256 id) external {
        EventInfo storage e = _at(id);
        if (!e.cancelled) revert NotCancelled();

        uint256 owed = paidBy[id][msg.sender];
        if (owed == 0) revert NothingToRefund();
        paidBy[id][msg.sender] = 0; // zero before transfer

        uint256 held = balanceOf(msg.sender, id);
        if (held > 0) _burn(msg.sender, id, held);

        token.safeTransfer(msg.sender, owed);
        emit Refunded(id, msg.sender, owed);
    }

    /// The organiser is paid once the event has started, not before.
    function withdrawProceeds(uint256 id) external {
        EventInfo storage e = _at(id);
        if (e.organiser != msg.sender) revert NotTheOrganiser(e.organiser);
        if (e.cancelled) revert EventCancelledError();
        if (block.timestamp < e.startsAt) revert EventNotStarted();
        if (e.withdrawn) revert AlreadyWithdrawn();

        e.withdrawn = true;
        uint256 amount = e.price * e.sold;
        if (amount > 0) token.safeTransfer(e.organiser, amount);
        emit ProceedsWithdrawn(id, e.organiser, amount);
    }

    /// Metadata generated on chain — no server to keep running for five years.
    function uri(uint256 id) public view override returns (string memory) {
        EventInfo storage e = _at(id);
        string memory json = string.concat(
            '{"name":"',
            e.name,
            '","description":"Trustville event ticket","attributes":[{"trait_type":"Event","value":',
            Strings.toString(id),
            '},{"trait_type":"Capacity","value":',
            Strings.toString(e.capacity),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function count() external view returns (uint256) {
        return _events.length;
    }

    function get(uint256 id) external view returns (EventInfo memory) {
        return _at(id);
    }

    function _at(uint256 id) internal view returns (EventInfo storage) {
        if (id == 0 || id > _events.length) revert NoSuchEvent();
        return _events[id - 1];
    }
}
