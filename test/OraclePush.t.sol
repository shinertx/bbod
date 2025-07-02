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

    function _sig(uint256 fee, uint256 slot) internal view returns(bytes[] memory sigs){
        bytes32 h = keccak256(abi.encodePacked("BLOB_FEE", fee, slot));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(signer)), h.toEthSignedMessageHash());
        sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
    }

    function testCannotPushTwiceSameSlot() public {
        uint256 fee = 100;
        uint256 slot = block.timestamp / 12;
        bytes[] memory sigs = _sig(fee, slot);
        oracle.push(fee, sigs);
        vm.expectRevert("already-pushed");
        oracle.push(fee, sigs);
    }
}
