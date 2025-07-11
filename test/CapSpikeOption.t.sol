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
        vm.deal(buyer, 5 ether); // Fund the buyer
    }

    function testCapSpike() public {
        uint256 strike = 100;
        uint256 cap = 120;
        uint256 maxSold = 10;
        uint256 maxPay = (cap - strike) * 1 gwei * maxSold;
        uint256 expiry = block.timestamp + 3601;

        // writer create series with margin
        desk.create{value: maxPay}(1, strike, cap, expiry, maxSold);

        // buyer purchase to create open interest
        uint256 prem = desk.premium(strike, expiry);
        vm.deal(address(1), prem);
        vm.prank(address(1));
        desk.buy{value: prem}(1, 1);

        // warp to expiry+1 and push fee above cap
        vm.warp(expiry + 1);
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
        (, , , , , uint256 payWei, , ) = desk.series(1);
        assertEq(payWei, (cap - strike) * 1 gwei);
    }

    function testBuy() public {
        // series has a high K, so it's cheap
        uint256 expiry_ = block.timestamp + 3601;
        desk.create{value: 1 ether}(1, 100, 120, expiry_, 10);
        (
            address writer_addr,
            uint256 strike,
            uint256 cap,
            uint256 expiry,
            uint256 sold,
            uint256 payoutPerUnit,
            uint256 margin,
            bool paidOut
        ) = desk.series(1);
        vm.startPrank(buyer);
        uint256 expectedPremium = desk.premium(100, expiry);
        desk.buy{value: expectedPremium}(1, 1);
        vm.stopPrank();

        // check that the series is no longer live
        (
            address writer2,
            uint256 strike2,
            uint256 cap2,
            uint256 expiry2,
            uint256 sold2,
            uint256 payoutPerUnit2,
            uint256 margin2,
            bool paidOut2
        ) = desk.series(1);
        assertEq(writer2, writer_addr);
        assertEq(strike2, 100);
        assertEq(expiry2, expiry);
        assertEq(margin2, margin);
        assertEq(sold2, 1);
        assertEq(paidOut2, false);
    }
}