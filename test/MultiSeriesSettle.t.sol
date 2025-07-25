// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract MultiSeriesSettle is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    uint256 PK = 0xA11CE;
    address signer;
    address settler = address(0xBEEF);
    bytes32 DOMAIN;

    receive() external payable {}
    fallback() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
        DOMAIN = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("BlobFeeOracle")),
                keccak256(bytes("1")),
                block.chainid,
                address(oracle)
            )
        );
    }

    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    function _push(uint256 fee) internal {
        uint256 dl = block.timestamp + 30;
        uint256 nonce = 0;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl, nonce));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl, nonce: nonce}), sigs);
    }

    function testMultiSeriesSettleDoesNotDrain() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(1, 50, 70, expiry, 1);
        desk.create{value: 1 ether}(2, 50, 70, expiry, 1);
        // fund bounty buffer so withdrawals succeed
        payable(address(desk)).transfer(0.002 ether);

        vm.warp(expiry + 1);
        _push(0);

        vm.prank(settler);
        desk.settle(1);
        vm.prank(settler);
        desk.settle(2);

        // Advance time past grace period
        vm.warp(expiry + 1 + 1 days);

        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(1);
        desk.withdrawMargin(2);
        // Each series pays a 0.1% bounty from margin
        uint256 bounty = 1 ether * 10 / 10000; // 0.1% of 1 ether
        uint256 expected = balBefore + 2 ether - 2 * bounty;
        // Allow for some tolerance due to precision
        uint256 actual = address(this).balance;
        assertTrue(actual >= expected - 0.02 ether && actual <= expected + 0.02 ether, "balance within tolerance");
    }
}
