// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract BBODSweep is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    uint256 PK = 0xA11CE;
    address signer;

    function setUp() public {
        signer = vm.addr(PK);
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function _push(uint256 fee) internal {
        bytes32 h = keccak256(abi.encodePacked("BLOB_FEE", fee, block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, h.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(fee, sigs);
    }

    function testSweepMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(1, 100, 120, expiry, 1);
        vm.warp(expiry + 1);
        _push(90); // below strike => OTM
        desk.settle(1);
        uint256 balBefore = address(this).balance;
        desk.sweepMargin(1);
        assertEq(address(this).balance, balBefore + 1 ether);
    }
}
