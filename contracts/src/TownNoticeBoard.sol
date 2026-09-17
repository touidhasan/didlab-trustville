// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Trustville Town Notice Board
/// @notice D0 warm-up contract: anyone can post a short public notice.
///         Shows the three basics every later module builds on —
///         state, events, and who signed the transaction (msg.sender).
contract TownNoticeBoard {
    struct Notice {
        address author;
        uint64 postedAt;
        string text;
    }

    uint256 public constant MAX_LENGTH = 140;

    Notice[] private _notices;

    /// @notice Emitted on every post. Indexers and the explorer read this.
    event NoticePosted(uint256 indexed id, address indexed author, string text);

    error EmptyNotice();
    error NoticeTooLong(uint256 length, uint256 max);

    function post(string calldata text) external returns (uint256 id) {
        uint256 len = bytes(text).length;
        if (len == 0) revert EmptyNotice();
        if (len > MAX_LENGTH) revert NoticeTooLong(len, MAX_LENGTH);

        id = _notices.length;
        _notices.push(Notice({author: msg.sender, postedAt: uint64(block.timestamp), text: text}));
        emit NoticePosted(id, msg.sender, text);
    }

    function count() external view returns (uint256) {
        return _notices.length;
    }

    function get(uint256 id) external view returns (Notice memory) {
        return _notices[id];
    }
}
