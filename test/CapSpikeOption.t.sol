// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract CapSpikeOptionTest is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    address writer = address(this);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;

    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function testCapSpike() public {
        uint256 strike = 100;
        uint256 cap = 120;
        uint256 maxSold = 10;
        uint256 maxPay = (cap - strike) * 1 gwei * maxSold;

        // writer create series with margin
        desk.create{value: maxPay}(1, strike, cap, block.timestamp + 1, maxSold);

        // buyer purchase to create open interest
        uint256 prem = desk.premium(strike, block.timestamp + 1);
        vm.deal(address(1), prem);
        vm.prank(address(1));
        desk.buy{value: prem}(1, 1);

        // warp to expiry+1 and push fee above cap
        vm.warp(block.timestamp + 2);
        uint256 fee = 200;
        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", fee, block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(fee, sigs); // fee higher than cap

        desk.settle(1);
        (,,, , uint256 payWei,,) = desk.series(1);
        assertEq(payWei, (cap - strike) * 1 gwei);
    }
} 