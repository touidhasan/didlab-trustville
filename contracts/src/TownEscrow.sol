// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Market Escrow  (module 5)
/// @notice Problem: buying from a stranger. Someone has to move first, and whoever does
///         carries all the risk.
/// @dev    The money sits in the contract, not with either party. The buyer confirms and
///         the seller is paid; if the buyer goes quiet, the seller can claim after the
///         dispute window; if something is wrong, the buyer disputes and an arbiter
///         decides. Nobody can take the funds unilaterally.
contract TownEscrow is AccessControl, Stamping {
    using SafeERC20 for IERC20;

    bytes32 public constant ARBITER_ROLE = keccak256("ARBITER_ROLE");
    uint16 public constant MODULE_ID = 5;

    uint64 public constant MIN_WINDOW = 1 minutes;
    uint64 public constant MAX_WINDOW = 30 days;

    enum State {
        None,
        Funded,
        Released,
        Refunded,
        Disputed
    }

    struct Order {
        address buyer;
        address seller;
        uint256 amount;
        uint256 productId; // 0 if not tied to a registered product
        uint64 deadline; // seller may claim after this
        State state;
    }

    IERC20 public immutable token;

    Order[] private _orders; // index + 1 == public id
    mapping(address => uint256[]) private _byParty;

    event OrderCreated(
        uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount, uint64 deadline
    );
    event Released(uint256 indexed id, address indexed to, uint256 amount);
    event Refunded(uint256 indexed id, address indexed to, uint256 amount);
    event Disputed(uint256 indexed id, address indexed by);
    event Resolved(uint256 indexed id, address indexed arbiter, bool paidSeller);

    error BadWindow();
    error ZeroAmount();
    error SellerIsBuyer();
    error NoSuchOrder();
    error NotTheBuyer();
    error NotTheSeller();
    error WrongState(State state);
    error TooEarly(uint64 deadline);

    constructor(address admin, IERC20 token_, TrustvillePassport passport_) Stamping(passport_) {
        token = token_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ARBITER_ROLE, admin);
    }

    /// Buyer funds the order. Requires an ERC-20 approval for `amount` first.
    function createOrder(address seller, uint256 amount, uint256 productId, uint64 window)
        external
        returns (uint256 id)
    {
        if (amount == 0) revert ZeroAmount();
        if (seller == msg.sender) revert SellerIsBuyer();
        if (window < MIN_WINDOW || window > MAX_WINDOW) revert BadWindow();

        _orders.push(
            Order({
                buyer: msg.sender,
                seller: seller,
                amount: amount,
                productId: productId,
                deadline: uint64(block.timestamp) + window,
                state: State.Funded
            })
        );
        id = _orders.length;
        _byParty[msg.sender].push(id);
        _byParty[seller].push(id);

        token.safeTransferFrom(msg.sender, address(this), amount);
        emit OrderCreated(id, msg.sender, seller, amount, _orders[id - 1].deadline);
    }

    /// Happy path: the buyer got the goods.
    function confirmReceipt(uint256 id) external {
        Order storage o = _at(id);
        if (msg.sender != o.buyer) revert NotTheBuyer();
        if (o.state != State.Funded) revert WrongState(o.state);

        o.state = State.Released; // state before transfer — reentrancy
        token.safeTransfer(o.seller, o.amount);
        emit Released(id, o.seller, o.amount);
        _stamp(o.buyer, MODULE_ID);
    }

    /// Buyer went quiet: after the window the seller may take payment.
    function claimAfterWindow(uint256 id) external {
        Order storage o = _at(id);
        if (msg.sender != o.seller) revert NotTheSeller();
        if (o.state != State.Funded) revert WrongState(o.state);
        if (block.timestamp < o.deadline) revert TooEarly(o.deadline);

        o.state = State.Released;
        token.safeTransfer(o.seller, o.amount);
        emit Released(id, o.seller, o.amount);
    }

    /// Something is wrong — freeze the order for an arbiter.
    function dispute(uint256 id) external {
        Order storage o = _at(id);
        if (msg.sender != o.buyer) revert NotTheBuyer();
        if (o.state != State.Funded) revert WrongState(o.state);

        o.state = State.Disputed;
        emit Disputed(id, msg.sender);
    }

    /// The arbiter decides. This is the honest weak point of escrow: someone must judge,
    /// and code cannot tell whether a box arrived empty.
    function resolve(uint256 id, bool paySeller) external onlyRole(ARBITER_ROLE) {
        Order storage o = _at(id);
        if (o.state != State.Disputed) revert WrongState(o.state);

        address to = paySeller ? o.seller : o.buyer;
        o.state = paySeller ? State.Released : State.Refunded;
        token.safeTransfer(to, o.amount);

        if (paySeller) emit Released(id, to, o.amount);
        else emit Refunded(id, to, o.amount);
        emit Resolved(id, msg.sender, paySeller);
    }

    function count() external view returns (uint256) {
        return _orders.length;
    }

    function get(uint256 id) external view returns (Order memory) {
        return _at(id);
    }

    function ordersOf(address party) external view returns (uint256[] memory) {
        return _byParty[party];
    }

    function _at(uint256 id) internal view returns (Order storage) {
        if (id == 0 || id > _orders.length) revert NoSuchOrder();
        return _orders[id - 1];
    }
}
