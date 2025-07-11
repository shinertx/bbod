// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";

contract BountySize is Test {
    CommitRevealBSP pm;
    function setUp() public {
        pm = new CommitRevealBSP(address(0));
    }

    receive() external payable {}

    function testBountyIgnoresGifts() public {
        // fund pools
        vm.prank(address(1));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(1), CommitRevealBSP.Side.Hi, bytes32("s"))));
        vm.warp(block.timestamp + 301);
        vm.prank(address(1));
        pm.reveal(CommitRevealBSP.Side.Hi, bytes32("s"));
        (, , uint256 revealTs,,,,,,,,) = pm.rounds(1);
        vm.warp(revealTs + 1);
        // gift ETH to inflate address balance
        (bool ok,) = address(pm).call{value: 5 ether}("");
        require(ok, "gift failed");
        uint256 balBefore = address(this).balance;
        pm.settle();
        assertEq(address(this).balance - balBefore, 0); // bounty is zero due to zero pool
    }
}
