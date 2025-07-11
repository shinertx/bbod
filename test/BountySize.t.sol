// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/IBlobBaseFee.sol";

contract DummyOracle is IBlobBaseFee {
    uint256 public fee;
    function blobBaseFee() external view returns (uint256) { return fee; }
    function set(uint256 f) external { fee = f; }
}

contract BountySize is Test {
    CommitRevealBSP pm;
    DummyOracle oracle;
    function setUp() public {
        oracle = new DummyOracle();
        pm = new CommitRevealBSP(address(oracle));
        vm.deal(address(this), 7 ether); // fund test contract for commit and gift
        vm.deal(address(1), 2 ether);    // fund actor for commit
    }

    receive() external payable {}

    function testBountyIgnoresGifts() public {
        // fund pools
        vm.prank(address(1));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(1), CommitRevealBSP.Side.Hi, bytes32("s"))));
        vm.prank(address(2));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(2), CommitRevealBSP.Side.Lo, bytes32("s2"))));
        vm.warp(block.timestamp + 301);
        vm.prank(address(1));
        pm.reveal(CommitRevealBSP.Side.Hi, bytes32("s"));
        vm.prank(address(2));
        pm.reveal(CommitRevealBSP.Side.Lo, bytes32("s2"));
        (, , uint256 revealTs,,,,,,,,) = pm.rounds(1);
        vm.warp(revealTs + 1);
        // gift ETH to inflate address balance
        (bool ok,) = address(pm).call{value: 5 ether}("");
        require(ok, "gift failed");
        uint256 balBefore = address(this).balance;
        pm.settle();
        assertEq(address(this).balance - balBefore, 2 ether * 10 / 10_000); // bounty is 0.1% of 2 ether
    }
}
