// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/BlobFeeOracle.sol";

contract ThresholdRevealEnforcement is Test {
    CommitRevealBSP pm;
    BlobFeeOracle oracle;
    address bettor = address(0xCAFE);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;

    bytes32 DOMAIN_SEPARATOR;
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        pm = new CommitRevealBSP(address(oracle));
        vm.deal(address(this), 10 ether);
    }

    function testSettleRevertsIfUnrevealed() public {
        // Settle round 1 by waiting for timeout
        (, , uint256 revealTs1,,,,,,,,) = pm.rounds(1);
        vm.warp(revealTs1 + pm.THRESHOLD_REVEAL_TIMEOUT() + 1);
        pm.settle();

        // commit threshold for next round (round 2)
        bytes32 h = keccak256(abi.encodePacked(uint256(50), uint256(1)));
        pm.commitThreshold(h);

        // attempt to settle round 2 without revealing threshold, before timeout
        (, , uint256 revealTs2,,,,,,,,) = pm.rounds(2);
        vm.warp(revealTs2 + 1);
        vm.expectRevert(bytes("!reveal"));
        pm.settle();
    }

    function testSettleAfterTimeoutUsesPrevThreshold() public {
        bytes32 h = keccak256(abi.encodePacked(uint256(75), uint256(1)));
        pm.commitThreshold(h);

        // settle round 1 via timeout
        (, , uint256 revealTs1,,,,,,,,) = pm.rounds(1);
        vm.warp(revealTs1 + pm.THRESHOLD_REVEAL_TIMEOUT() + 1);
        pm.settle();

        // get round 1 threshold for later comparison
        (, , , , , , , uint256 thr1,,,) = pm.rounds(1);

        // settle round 2 via timeout
        (, , uint256 revealTs2,,,,,,,,) = pm.rounds(2);
        vm.warp(revealTs2 + pm.THRESHOLD_REVEAL_TIMEOUT() + 1);
        pm.settle();

        // After timeout, round 2 should have used round 1's threshold.
        // Round 3 should be created with round 2's threshold.
        (, , , , , , , uint256 thr2,,,) = pm.rounds(2);
        (, , , , , , , uint256 thr3,,,) = pm.rounds(3);
        assertEq(thr1, 100 * 1 gwei, "initial threshold not carried to r1");
        assertEq(thr2, thr1, "fallback threshold not used for round 2");
        assertEq(thr3, thr2, "round 3 threshold incorrect");
    }
}
