// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/BlobFeeOracle.sol";

contract BSPFuzz is Test {
    CommitRevealBSP pm;
    BlobFeeOracle oracle;
    address bettor = address(0xCAFE);
    address[] signers;
    
    // allow this contract to receive ether (rake)
    receive() external payable {}

    function setUp() public {
        signers.push(address(this));
        oracle = new BlobFeeOracle(signers, 1);
        pm = new CommitRevealBSP(address(oracle));
    }

    function testFuzz_FullCycle(uint96 betAmount, uint96 finalFee) public {
        betAmount = uint96(bound(betAmount, 1, 1e18));
        finalFee = uint96(bound(finalFee, 0, 200));

        // 1. Bettor commits HI
        vm.deal(bettor, betAmount);
        bytes32 salt = keccak256("mysecret");
        bytes32 commit = keccak256(abi.encodePacked(bettor, CommitRevealBSP.Side.Hi, salt));
        vm.prank(bettor);
        pm.commit{value: betAmount}(commit);

        // 2. Forward to reveal phase
        vm.warp(block.timestamp + 301);

        vm.prank(bettor);
        pm.reveal(CommitRevealBSP.Side.Hi, salt);

        // 3. Forward to settlement (after reveal window end)
        ( , , uint256 revealTs, , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);

        vm.prank(address(this));
        oracle.push(finalFee);

        pm.settle();

        // 4. Claim
        vm.prank(bettor);
        pm.claim(1, CommitRevealBSP.Side.Hi, salt);
    }
} 