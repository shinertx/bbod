// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";

contract OraclePushTest is Test {
    BlobFeeOracle oracle;
    address[] signers;
    uint256[] privateKeys;

    bytes32 constant FEED_TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline,uint256 nonce)");

    function setUp() public {
        // Setup 3 signers
        for (uint i = 0; i < 3; i++) {
            uint256 pk = uint256(keccak256(abi.encodePacked("signer-", i)));
            privateKeys.push(pk);
            signers.push(vm.addr(pk));
        }
        oracle = new BlobFeeOracle(signers, 2); // 2 of 3 quorum
    }

    function _sign(uint256 privateKey, BlobFeeOracle.FeedMsg memory msg) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(FEED_TYPEHASH, msg.fee, msg.deadline, msg.nonce));
        bytes32 digest = EIP712.makeMessage(oracle.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function testPushSuccess() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(privateKeys[1], msgs[1]);

        oracle.push(msgs, sigs);
        (uint256 fee, ) = oracle.latest();
        assertEq(fee, 100);
        assertEq(oracle.nonces(signers[0]), 1);
        assertEq(oracle.nonces(signers[1]), 1);
    }

    function testDeadlineEnforced() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 1, nonce: 0});
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 1, nonce: 0});

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(privateKeys[1], msgs[1]);

        vm.warp(block.timestamp + 2);
        vm.expectRevert("Signature expired");
        oracle.push(msgs, sigs);
    }

    function testMismatchedFees() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 99, deadline: block.timestamp + 60, nonce: 0}); // Mismatched fee

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(privateKeys[1], msgs[1]);

        vm.expectRevert("Mismatched fees");
        oracle.push(msgs, sigs);
    }

    function testInvalidSigner() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(uint256(keccak256("invalid-signer")), msgs[1]); // Invalid signer

        vm.expectRevert("Invalid signer");
        oracle.push(msgs, sigs);
    }

    function testNonceReplay() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(privateKeys[1], msgs[1]);

        oracle.push(msgs, sigs); // First push successful

        // Try to replay the same signatures
        vm.expectRevert("Invalid nonce");
        oracle.push(msgs, sigs);
    }

     function testDuplicateSigner() public {
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](2);
        bytes[] memory sigs = new bytes[](2);

        msgs[0] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});
        // Note: msg[1] is identical to msg[0] for this test's purpose, but signed by a different key below
        msgs[1] = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 60, nonce: 0});

        sigs[0] = _sign(privateKeys[0], msgs[0]);
        sigs[1] = _sign(privateKeys[0], msgs[1]); // Signed by signer 0 again

        vm.expectRevert("Duplicate signer");
        oracle.push(msgs, sigs);
    }
}