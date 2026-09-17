// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TownNoticeBoard} from "../src/TownNoticeBoard.sol";

contract TownNoticeBoardTest is Test {
    TownNoticeBoard board;
    address alice = makeAddr("alice");

    event NoticePosted(uint256 indexed id, address indexed author, string text);

    function setUp() public {
        board = new TownNoticeBoard();
    }

    function test_PostStoresAuthorAndText() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit NoticePosted(0, alice, "Market opens at 9");
        uint256 id = board.post("Market opens at 9");

        assertEq(id, 0);
        assertEq(board.count(), 1);
        TownNoticeBoard.Notice memory n = board.get(0);
        assertEq(n.author, alice);
        assertEq(n.text, "Market opens at 9");
    }

    function test_RevertsOnEmpty() public {
        vm.expectRevert(TownNoticeBoard.EmptyNotice.selector);
        board.post("");
    }

    function test_RevertsWhenTooLong() public {
        string memory tooLong = string(new bytes(141));
        vm.expectRevert(abi.encodeWithSelector(TownNoticeBoard.NoticeTooLong.selector, 141, 140));
        board.post(tooLong);
    }
}
