// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract OracleSlotFinality is Test {
    BlobFeeOracle oracle;
    address signer = address(this);
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
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

    function _sig(uint256 fee, uint256 dl) internal view returns(bytes[] memory sigs){
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    function testSlotSinglePush() public {
        uint256 dl = block.timestamp + 30;
        bytes[] memory sigs = _sig(50, dl);
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](1);
        msgs[0] = BlobFeeOracle.FeedMsg({fee:50, deadline:dl});
        oracle.push(msgs, sigs);
        vm.expectRevert("already-pushed");
        oracle.push(msgs, sigs);
    }
}
