// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Stamping} from "./Stamping.sol";
import {TrustvillePassport} from "./TrustvillePassport.sol";

/// @title Trustville Sealed-Bid Auction  (module 6)
/// @notice Problem: on a public ledger every bid is visible, so whoever looks last wins.
/// @dev    Commit–reveal. First you publish only a HASH of your bid; nobody can read it.
///         After the commit phase closes, you reveal the amount and the salt, and the
///         contract checks the hash matches. A bid that is never revealed simply loses.
///
///         Two honest limitations, both worth discussing in class:
///         - Nothing is staked at commit time, so a bidder can walk away costlessly.
///           A real auction takes a deposit; that is the first suggested extension.
///         - Refunds are PULL, not push: losers call withdraw(). Pushing tokens to a
///           list of losers is how auctions get stuck when one transfer fails.
contract SealedAuction is Stamping {
    using SafeERC20 for IERC20;

    uint16 public constant MODULE_ID = 6;
    uint64 public constant MIN_PHASE = 30 seconds;
    uint64 public constant MAX_PHASE = 7 days;

    struct Auction {
        address seller;
        uint256 productId;
        uint64 commitEnd;
        uint64 revealEnd;
        address highBidder;
        uint256 highBid;
        bool settled;
        string title;
    }

    IERC20 public immutable token;

    Auction[] private _auctions; // index + 1 == public id
    mapping(uint256 => mapping(address => bytes32)) public commitmentOf;
    mapping(uint256 => mapping(address => bool)) public revealed;
    mapping(address => uint256) public refunds;

    event AuctionCreated(uint256 indexed id, address indexed seller, string title, uint64 commitEnd, uint64 revealEnd);
    event BidCommitted(uint256 indexed id, address indexed bidder);
    event BidRevealed(uint256 indexed id, address indexed bidder, uint256 amount, bool leading);
    event Settled(uint256 indexed id, address indexed winner, uint256 amount);
    event RefundWithdrawn(address indexed bidder, uint256 amount);

    error BadPhaseLength();
    error NoSuchAuction();
    error NotInCommitPhase();
    error NotInRevealPhase();
    error RevealNotOver();
    error AlreadyCommitted();
    error NothingCommitted();
    error AlreadyRevealed();
    error BadReveal();
    error AlreadySettled();
    error SellerCannotBid();
    error NothingToWithdraw();

    constructor(IERC20 token_, TrustvillePassport passport_) Stamping(passport_) {
        token = token_;
    }

    function createAuction(string calldata title, uint256 productId, uint64 commitSecs, uint64 revealSecs)
        external
        returns (uint256 id)
    {
        // Bounds only: the seller picks the pace. Thirty seconds is enough to demonstrate
        // commit-reveal in a lecture; a week suits a real sale.
        if (commitSecs < MIN_PHASE || revealSecs < MIN_PHASE) revert BadPhaseLength();
        if (commitSecs > MAX_PHASE || revealSecs > MAX_PHASE) revert BadPhaseLength();

        uint64 commitEnd = uint64(block.timestamp) + commitSecs;
        _auctions.push(
            Auction({
                seller: msg.sender,
                productId: productId,
                commitEnd: commitEnd,
                revealEnd: commitEnd + revealSecs,
                highBidder: address(0),
                highBid: 0,
                settled: false,
                title: title
            })
        );
        id = _auctions.length;
        emit AuctionCreated(id, msg.sender, title, commitEnd, _auctions[id - 1].revealEnd);
    }

    /// commitment = keccak256(abi.encodePacked(msg.sender, amount, salt))
    /// Keep the salt! Lose it and you cannot reveal, and your bid is void.
    function commitBid(uint256 id, bytes32 commitment) external {
        Auction storage a = _at(id);
        if (msg.sender == a.seller) revert SellerCannotBid();
        if (block.timestamp >= a.commitEnd) revert NotInCommitPhase();
        if (commitmentOf[id][msg.sender] != bytes32(0)) revert AlreadyCommitted();

        commitmentOf[id][msg.sender] = commitment;
        emit BidCommitted(id, msg.sender);
    }

    /// Reveal moves the tokens: the winner's stay in the contract, losers become refunds.
    function revealBid(uint256 id, uint256 amount, bytes32 salt) external {
        Auction storage a = _at(id);
        if (block.timestamp < a.commitEnd || block.timestamp >= a.revealEnd) revert NotInRevealPhase();

        bytes32 commitment = commitmentOf[id][msg.sender];
        if (commitment == bytes32(0)) revert NothingCommitted();
        if (revealed[id][msg.sender]) revert AlreadyRevealed();
        if (keccak256(abi.encodePacked(msg.sender, amount, salt)) != commitment) revert BadReveal();

        revealed[id][msg.sender] = true;
        token.safeTransferFrom(msg.sender, address(this), amount);

        bool leading = amount > a.highBid;
        if (leading) {
            if (a.highBidder != address(0)) refunds[a.highBidder] += a.highBid; // outbid, claim later
            a.highBidder = msg.sender;
            a.highBid = amount;
        } else {
            refunds[msg.sender] += amount; // did not win: withdraw it back
        }

        emit BidRevealed(id, msg.sender, amount, leading);
        _stamp(msg.sender, MODULE_ID);
    }

    function settle(uint256 id) external {
        Auction storage a = _at(id);
        if (block.timestamp < a.revealEnd) revert RevealNotOver();
        if (a.settled) revert AlreadySettled();

        a.settled = true;
        if (a.highBidder != address(0)) {
            token.safeTransfer(a.seller, a.highBid);
        }
        emit Settled(id, a.highBidder, a.highBid);
    }

    function withdrawRefund() external {
        uint256 owed = refunds[msg.sender];
        if (owed == 0) revert NothingToWithdraw();
        refunds[msg.sender] = 0; // zero before transfer
        token.safeTransfer(msg.sender, owed);
        emit RefundWithdrawn(msg.sender, owed);
    }

    function count() external view returns (uint256) {
        return _auctions.length;
    }

    function get(uint256 id) external view returns (Auction memory) {
        return _at(id);
    }

    /// Helper so the UI and tests build the commitment the same way the contract checks it.
    function hashBid(address bidder, uint256 amount, bytes32 salt) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(bidder, amount, salt));
    }

    function _at(uint256 id) internal view returns (Auction storage) {
        if (id == 0 || id > _auctions.length) revert NoSuchAuction();
        return _auctions[id - 1];
    }
}
