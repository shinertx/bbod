// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract OraclePushTest is Test {
    BlobFeeOracle oracle;
    address signer = address(this);

    function setUp() public {
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
    }

    bytes32 constant DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("BlobFeeOracle")),
            keccak256(bytes("1")),
            block.chainid,
            address(oracle)
        )
    );
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    function _sig(uint256 fee, uint256 dl) internal view returns(bytes[] memory sigs){
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    function testDeadlineEnforced() public {
        BlobFeeOracle.FeedMsg memory m = BlobFeeOracle.FeedMsg({fee: 100, deadline: block.timestamp + 1});
        bytes[] memory sigs = _sig(m.fee, m.deadline);
        vm.warp(m.deadline + 1);
        vm.expectRevert();
        oracle.push(m, sigs);
    }

    function testMismatchedSignature() public {
        uint256 dl = block.timestamp + 30;
        bytes[] memory sigs = _sig(99, dl); // signer signed different fee
        vm.expectRevert();
        oracle.push(BlobFeeOracle.FeedMsg({fee: 100, deadline: dl}), sigs);
    }
}
