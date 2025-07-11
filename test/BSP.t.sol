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

    bytes32 DOMAIN_SEPARATOR;
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");
    
    // allow this contract to receive ether (rake)
    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        pm = new CommitRevealBSP(address(oracle));
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("BlobFeeOracle")),
                keccak256(bytes("1")),
                block.chainid,
                address(oracle)
            )
        );
    }

    function testFuzz_FullCycle(uint96 betAmount, uint96 finalFee) public {
        betAmount = uint96(bound(betAmount, 0.01 ether, 1e18));
        finalFee = uint96(bound(finalFee, 1, 200)); // cannot be 0

        // 1. Bettor commits HI
        vm.deal(bettor, betAmount);
        bytes32 salt = keccak256("mysecret");
        bytes32 commit = keccak256(abi.encodePacked(bettor, CommitRevealBSP.Side.Hi, salt));
        vm.prank(bettor);
        pm.commit{value: betAmount}(commit);

        // 2. Forward to reveal phase
        (, uint256 closeTs, , , , , , , , , ) = pm.rounds(1);
        vm.warp(closeTs);

        vm.prank(bettor);
        pm.reveal(CommitRevealBSP.Side.Hi, salt);

        // 3. Forward to settlement (after reveal window end)
        ( , , uint256 revealTs, , , , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);

        uint256 finalFeeWei = uint256(finalFee) * 1 gwei;
        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, finalFeeWei, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: finalFeeWei, deadline: dl}), sigs);

        pm.settle();

        // 4. Claim
        vm.prank(bettor);
        pm.claim(1, CommitRevealBSP.Side.Hi, salt);
    }

    function testCommitRevealThreshold(uint96 fee) public {
        fee = uint96(bound(fee, 5, 100)); // fee in gwei
        uint256 feeWei = uint256(fee) * 1 gwei;

        // commit threshold for next round
        bytes32 h = keccak256(abi.encodePacked(feeWei, uint256(1)));
        pm.commitThreshold(h);

        // bettor commits
        vm.deal(bettor, 1 ether);
        bytes32 salt = keccak256("s");
        bytes32 bet = keccak256(abi.encodePacked(bettor, CommitRevealBSP.Side.Hi, salt));
        vm.prank(bettor);
        pm.commit{value: 1 ether}(bet);

        (, uint256 closeTs, , , , , , , , , ) = pm.rounds(1);
        vm.warp(closeTs);
        vm.prank(bettor);
        pm.reveal(CommitRevealBSP.Side.Hi, salt);

        (, , uint256 revealTs, , , , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);

        pm.revealThreshold(feeWei, 1);

        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, feeWei, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: feeWei, deadline: dl}), sigs);

        pm.settle();
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

        (, uint256 closeTs, , , , , , , , , ) = pm.rounds(1);
        vm.warp(closeTs);
        vm.prank(hi);
        pm.reveal(CommitRevealBSP.Side.Hi, saltH);

        (, , uint256 revealTs, , , , , , , , ) = pm.rounds(1);
        vm.warp(revealTs + 1);
        uint256 dl3 = block.timestamp + 30;
        bytes32 structHash3 = keccak256(abi.encode(TYPEHASH, uint256(100), dl3));
        bytes32 digest3 = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash3);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest3);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: 100, deadline: dl3}), sigs);
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
