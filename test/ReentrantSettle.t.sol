// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";

contract Attacker {
    CommitRevealBSP pm;
    constructor(address p) { pm = CommitRevealBSP(payable(p)); }
    receive() external payable {
        try pm.settle() {} catch {}
    }
    function attack() external { pm.settle(); }
}

contract ReentrantSettle is Test {
    CommitRevealBSP pm;
    Attacker atk;
    function setUp() public {
        pm = new CommitRevealBSP(address(0));
        atk = new Attacker(address(pm));
    }

    function testReentrancyGuard() public {
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(atk), CommitRevealBSP.Side.Hi, bytes32("s"))));
        vm.warp(block.timestamp + 301);
        vm.prank(address(atk));
        pm.reveal(CommitRevealBSP.Side.Hi, bytes32("s"));
        (, , uint256 revealTs, , , , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);
        vm.prank(address(atk));
        vm.expectRevert();
        atk.attack();
    }
}
