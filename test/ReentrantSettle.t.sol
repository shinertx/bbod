// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/IBlobBaseFee.sol";

contract MockOracle is IBlobBaseFee {
    uint256 public fee;
    function blobBaseFee() external view returns (uint256) {
        return fee;
    }
    function setFee(uint256 _fee) external {
        fee = _fee;
    }
}

contract Attacker {
    CommitRevealBSP pm;
    constructor(address p) { pm = CommitRevealBSP(payable(p)); }
    receive() external payable {
        pm.settle();
    }
    function attack() external { pm.settle(); }
}

contract ReentrantSettle is Test {
    CommitRevealBSP pm;
    Attacker atk;
    address alice = makeAddr("alice");
    MockOracle oracle;

    function setUp() public {
        oracle = new MockOracle();
        pm = new CommitRevealBSP(address(oracle));
        atk = new Attacker(address(pm));
        vm.deal(address(atk), 2 ether); // fund attacker
        vm.deal(alice, 2 ether);        // fund alice
    }

    function testReentrancyGuard() public {
        oracle.setFee(30 * 1 gwei); // Set fee above default threshold of 25 gwei
        
        // Add threshold commit/reveal so settlement can proceed
        vm.prank(pm.owner());
        pm.commitThreshold(keccak256(abi.encodePacked(uint256(25 gwei), uint256(12345))));
        vm.prank(pm.owner());
        pm.revealThreshold(25 gwei, 12345);
        
        vm.prank(address(atk));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(atk), CommitRevealBSP.Side.Hi, bytes32("s"))));
        vm.prank(alice);
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(alice, CommitRevealBSP.Side.Lo, bytes32("s_alice"))));

        (, uint256 closeTs, , , , , , , , , , , , ) = pm.rounds(1);
        vm.warp(closeTs + 1);

        vm.prank(address(atk));
        pm.reveal(CommitRevealBSP.Side.Hi, bytes32("s"));
        vm.prank(alice);
        pm.reveal(CommitRevealBSP.Side.Lo, bytes32("s_alice"));

        (, , uint256 revealTs, , , , , , , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);
        vm.prank(address(atk));
        vm.expectRevert(bytes("xfer"));
        atk.attack();
    }
}
