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
    uint256 signerKey;
    address signer;
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline,uint256 nonce)");
    bytes32 DOMAIN_SEPARATOR;

    function setUp() public {
        (signer, signerKey) = makeAddrAndKey("signer");
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        DOMAIN_SEPARATOR = oracle.DOMAIN_SEPARATOR();
    }

    function _sig(uint256 fee, uint256 dl, uint256 nonce) internal view returns(bytes[] memory sigs){
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl, nonce));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    function testSlotSinglePush() public {
        uint256 dl = block.timestamp + 30;
        uint256 nonce = 0;
        bytes[] memory sigs = _sig(50, dl, nonce);
        oracle.push(BlobFeeOracle.FeedMsg({fee:50, deadline:dl, nonce:nonce}), sigs);
        vm.expectRevert("pushed");
        oracle.push(BlobFeeOracle.FeedMsg({fee:50, deadline:dl, nonce:nonce}), sigs);
    }
}
