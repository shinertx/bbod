// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";

contract WriterPremiumUnlock is Test {
    BlobOptionDesk desk;

    // allow contract to receive ETH during test
    receive() external payable {}

    function setUp() public {
        desk = new BlobOptionDesk(address(0));
    }

    function testUnlock() public {
        // writer (address(this)) opens a series
        uint256 id = 1;
        uint256 strike = 50;
        uint256 cap = 75;
        uint256 expiry = block.timestamp + 3600;
        uint256 maxSold = 10;
        desk.create{value: 1 ether}(id, strike, cap, expiry, maxSold);

        uint256 p = desk.premium(strike, expiry);

        // Simulate buyer address(1)
        vm.deal(address(1), p);
        vm.prank(address(1));
        desk.buy{value: p}(id, 1);

        // Fast-forward 1 hour so premiums unlock
        vm.warp(block.timestamp + 3601);

        uint256 balBefore = address(this).balance;
        desk.withdrawPremium(id);
        assertGt(address(this).balance, balBefore, "premium not released");
    }

    function testWithdrawTooEarly() public {
        uint256 id = 1;
        desk.create{value: 1 ether}(id, 50, 75, block.timestamp + 3600, 1);
        uint256 p = desk.premium(50, block.timestamp + 3600);
        vm.deal(address(1), p);
        vm.prank(address(1));
        desk.buy{value: p}(id, 1);
        vm.expectRevert("locked");
        desk.withdrawPremium(id);
    }
}

