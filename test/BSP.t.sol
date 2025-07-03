// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract BSPFuzz is Test {
    CommitRevealBSP pm;
    BlobFeeOracle oracle;
    address bettor = address(0xCAFE);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;
    
    // allow this contract to receive ether (rake)
    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        pm = new CommitRevealBSP(address(oracle));
    }

    function testFuzz_FullCycle(uint96 betAmount, uint96 finalFee) public {
        betAmount = uint96(bound(betAmount, 0.01 ether, 1e18));
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

        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", uint256(finalFee), block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(finalFee, sigs);

        pm.settle();

        // 4. Claim
        vm.prank(bettor);
        pm.claim(1, CommitRevealBSP.Side.Hi, salt);
    }

    function testCommitRevealThreshold(uint96 fee) public {
        fee = uint96(bound(fee, 5, 200));

        // commit threshold for next round
        bytes32 h = keccak256(abi.encodePacked(uint256(fee), uint256(1)));
        pm.commit(h);

        // bettor commits
        vm.deal(bettor, 1 ether);
        bytes32 salt = keccak256("s");
        bytes32 bet = keccak256(abi.encodePacked(bettor, CommitRevealBSP.Side.Hi, salt));
        vm.prank(bettor);
        pm.commit{value: 1 ether}(bet);

        vm.warp(block.timestamp + 301);
        vm.prank(bettor);
        pm.reveal(CommitRevealBSP.Side.Hi, salt);

        (, , uint256 revealTs,,,,,,) = pm.rounds(1);
        vm.warp(revealTs + 1);
        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", uint256(50), block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(50, sigs);
        pm.settle();

        // reveal threshold for round 2
        pm.reveal(fee, 1);
        (, , , , , , uint256 thr,,) = pm.rounds(2);
        assertEq(thr, fee);
    }
}
    function testNonRevealForfeit() public {
        address hi = address(0xA1);
        address lo = address(0xB1);
        vm.deal(hi, 1 ether);
        vm.deal(lo, 1 ether);
        bytes32 saltH = keccak256("h");
        bytes32 commitH = keccak256(abi.encodePacked(hi, CommitRevealBSP.Side.Hi, saltH));
        vm.prank(hi);
        pm.commit{value: 1 ether}(commitH);
        bytes32 saltL = keccak256("l");
        bytes32 commitL = keccak256(abi.encodePacked(lo, CommitRevealBSP.Side.Lo, saltL));
        vm.prank(lo);
        pm.commit{value: 1 ether}(commitL);

        vm.warp(block.timestamp + 301);
        vm.prank(hi);
        pm.reveal(CommitRevealBSP.Side.Hi, saltH);

        (, , uint256 revealTs,,,,,,) = pm.rounds(1);
        vm.warp(revealTs + 1);
        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", uint256(100), block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(100, sigs);
        pm.settle();

        vm.warp(block.timestamp + pm.GRACE_NONREVEAL() + 1);
        uint256 ownerBefore = address(this).balance;
        vm.prank(lo);
        pm.claim(1, CommitRevealBSP.Side.Lo, saltL);
        assertEq(lo.balance, 0, "refund");
        assertEq(address(this).balance, ownerBefore + 1 ether, "owner");

        vm.prank(hi);
        pm.claim(1, CommitRevealBSP.Side.Hi, saltH);
        assertEq(hi.balance, 0.995 ether, "hi refund");
    }
}
