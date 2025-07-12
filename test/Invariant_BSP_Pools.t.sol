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

    receive() external payable {}

    // simple invariant: after settle, gross pool equals hi+lo minus rake-bounty
    function testPoolsIntegrity() public {
        vm.prank(alice);
        bsp.commit{value:1 ether}(keccak256(abi.encodePacked(alice, uint8(0), bytes32("salt1"))));
        vm.prank(bob);
        bsp.commit{value:1.2 ether}(keccak256(abi.encodePacked(bob, uint8(1), bytes32("salt2"))));

        // fast forward to reveal window
        (, uint256 closeTs, uint256 revealTs,,,,,,,,,,,) = bsp.rounds(bsp.cur());
        vm.warp(closeTs);
        vm.prank(alice);
        bsp.reveal(CommitRevealBSP.Side.Hi, bytes32("salt1"));
        vm.prank(bob);
        bsp.reveal(CommitRevealBSP.Side.Lo, bytes32("salt2"));

        // settle phase
        vm.warp(revealTs + 2); // Account for settlement delay
        oracle.set(30); // some fee
        bsp.settle();
        uint256 prevRound = bsp.cur() - 1;
        (,,,,uint256 hiPool, uint256 loPool, , , , , , , , uint256 bounty) = bsp.rounds(prevRound);
        assertEq(hiPool+loPool, 2.2 ether);
        uint256 gross = hiPool + loPool;
        uint256 expectedBounty = gross * bsp.SETTLE_BOUNTY_BP() / 10_000;
        assertEq(bounty, expectedBounty);
    }
}