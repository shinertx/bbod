// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract OptionDeskEdge is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    uint256 PK = 0xA11CE;
    address signer;
    address buyer = address(0xB0B);
    bytes32 DOMAIN;

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

    // Allow the test contract to receive ETH
    receive() external payable {}

    function testBuyCutoff() public {
        uint256 expiry = block.timestamp + 2 hours;
        desk.create{value: 1 ether}(1, 50, 60, expiry, 1);
        _push(50);
        uint256 p = desk.premium(50, expiry);
        vm.warp(expiry - desk.BUY_CUTOFF() + 1);
        vm.deal(buyer, p);
        vm.prank(buyer);
        vm.expectRevert(bytes("too-late-to-buy"));
        desk.buy{value: p}(1, 1);
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

    function testWithdrawMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(3, 100, 120, expiry, 1);
        vm.warp(expiry + 1 hours);
        _push(50);
        desk.settle(3);
        vm.warp(expiry + desk.GRACE_PERIOD() + 1);
        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(3);
        uint256 bounty = 1 ether * desk.SETTLE_BOUNTY_BP() / 10_000;
        assertEq(address(this).balance, balBefore + 1 ether - bounty);
    }

    function testWithdrawMarginTooEarly() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(7, 100, 120, expiry, 1);
        vm.warp(expiry + 1 hours);
        _push(50);
        desk.settle(7);
        vm.warp(expiry + desk.GRACE_PERIOD() - 1 seconds);
        vm.expectRevert(bytes("grace"));
        desk.withdrawMargin(7);
    }

    function testSweepMarginAfterExercise() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(4, 50, 70, expiry, 1);
        uint256 prem = desk.premium(50, expiry);
        vm.deal(buyer, prem);
        vm.prank(buyer);
        desk.buy{value: prem}(4, 1);
        vm.warp(expiry + 1 hours);
        _push(60);
        desk.settle(4);
        vm.prank(buyer);
        desk.exercise(4, 1);
        vm.warp(expiry + desk.GRACE_PERIOD() + 1);
        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(4);
        assertGt(address(this).balance, balBefore);
    }

    function testSweepMarginTooEarly() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(4, 50, 70, expiry, 1);
        _push(50);
        uint256 prem = desk.premium(50, expiry);
        vm.deal(buyer, prem);
        vm.prank(buyer);
        desk.buy{value: prem}(4, 1);
        vm.warp(expiry + 1 hours);
        _push(60);
        desk.settle(4);
        vm.prank(buyer);
        desk.exercise(4, 1);
        vm.warp(expiry + desk.GRACE_PERIOD() - 1 seconds);
        vm.expectRevert(bytes("grace"));
        desk.withdrawMargin(4);
    }
}
