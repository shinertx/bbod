// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/IBlobBaseFee.sol";

contract DummyOracle is IBlobBaseFee {
    uint256 public fee;
    function blobBaseFee() external view returns (uint256) { return fee; }
    function set(uint256 f) external { fee = f; }
}

contract Invariant_BSP_Pools is Test {
    CommitRevealBSP bsp;
    DummyOracle oracle;

    // actors
    address alice = address(0x1);
    address bob   = address(0x2);

    function setUp() public {
        oracle = new DummyOracle();
        bsp = new CommitRevealBSP(address(oracle));
        vm.deal(alice, 100 ether);
        vm.deal(bob,   100 ether);
    }

    // simple invariant: after settle, gross pool equals hi+lo minus rake-bounty
    function testPoolsIntegrity() public {
        vm.prank(alice);
        bsp.commit{value:1 ether}(keccak256(abi.encodePacked(alice, 0, bytes32("salt1"))));
        vm.prank(bob);
        bsp.commit{value:1.2 ether}(keccak256(abi.encodePacked(bob, 1, bytes32("salt2"))));

        // fast forward to reveal window
        vm.warp(block.timestamp + 301);
        vm.prank(alice);
        bsp.reveal(CommitRevealBSP.Side.Hi, bytes32("salt1"));
        vm.prank(bob);
        bsp.reveal(CommitRevealBSP.Side.Lo, bytes32("salt2"));

        // settle phase
        vm.warp(block.timestamp + 300);
        oracle.set(30); // some fee
        bsp.settle();
        (,,,,uint256 rake,uint256 bounty,,,) = bsp.rounds(bsp.cur());
        (,,,uint256 hiPool,uint256 loPool,,,,,) = bsp.rounds(bsp.cur());
        assertEq(hiPool+loPool, 2.2 ether);
        assertEq(rake + bounty <= 2.2 ether, true);
    }
} 