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
    address buyer = address(0xB0B);
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
        desk.create{value: maxPay}(1, strike, cap, block.timestamp + 360, maxSold);

        // buyer purchase to create open interest
        uint256 prem = desk.premium(strike, block.timestamp + 360);
        vm.deal(address(1), prem);
        vm.prank(address(1));
        desk.buy{value: prem}(1, 1);

        // warp to expiry+1 and push fee above cap
        vm.warp(block.timestamp + 361);
        uint256 fee = 200;
        uint256 dl = block.timestamp + 30;
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("BlobFeeOracle")),
            keccak256(bytes("1")),
            block.chainid,
            address(oracle)
        ));
        bytes32 structHash = keccak256(abi.encode(keccak256("FeedMsg(uint256 fee,uint256 deadline)"), fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(domain, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl}), sigs); // fee higher than cap

        desk.settle(1);
        (, , , , uint256 payWei, , , ) = desk.series(1);
        assertEq(payWei, (cap - strike) * 1 gwei);
    }

    function testBuy() public {
        // series has a high K, so it's cheap
        (
            address writer_addr,
            uint256 k,
            uint256 expiry,
            uint256 premium,
            uint256 margin,
            uint256 maxSold,
            uint256 sold,
            bool live
        ) = desk.series(1);
        vm.startPrank(buyer);
        uint256 expectedPremium = desk.premium(1, 1e18);
        desk.buy{value: expectedPremium}(1, 1);
        vm.stopPrank();

        // check that the series is no longer live
        (address writer2, uint256 k2, uint256 expiry2, uint256 premium2, uint256 margin2, uint256 maxSold2, uint256 sold2, bool live2) = desk.series(1);
        assertEq(writer2, writer_addr);
        assertEq(k2, 1);
        assertEq(expiry2, expiry);
        assertEq(premium2, premium);
        assertEq(margin2, margin);
        assertEq(maxSold2, maxSold);
        assertEq(sold2, 1);
        assertEq(live2, false);
    }
}