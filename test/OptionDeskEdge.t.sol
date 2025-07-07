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

    function testBuyCutoff() public {
        uint256 expiry = block.timestamp + 1000;
        desk.create{value: 1 ether}(1, 50, 60, expiry, 1);
        vm.warp(expiry - 1);
        uint256 p = desk.premium(50, expiry);
        vm.deal(buyer, p);
        vm.prank(buyer);
        vm.expectRevert(bytes("too-late-to-buy"));
        desk.buy{value: p}(1, 1);
    }

    function testSetK() public {
        uint256 expiry = block.timestamp + 1 days;
        desk.create{value: 1 ether}(2, 50, 60, expiry, 1);
        uint256 oldP = desk.premium(50, expiry);
        desk.setK(1e17);
        uint256 newP = desk.premium(50, expiry);
        assertGt(newP, oldP, "premium not updated");
    }

    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    function _push(uint256 fee) internal {
        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl}), sigs);
    }

    function testWithdrawMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(3, 100, 120, expiry, 1);
        vm.warp(expiry + 1);
        _push(50);
        desk.settle(3);
        vm.warp(expiry + desk.GRACE_PERIOD() + 1);
        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(3);
        assertEq(address(this).balance, balBefore + 1 ether);
    }

    function testWithdrawMarginTooEarly() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(7, 100, 120, expiry, 1);
        vm.warp(expiry + 1);
        _push(50);
        desk.settle(7);
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
        vm.warp(expiry + 1);
        _push(60);
        desk.settle(4);
        vm.prank(buyer);
        desk.exercise(4);
        vm.warp(expiry + desk.GRACE_PERIOD() + 1);
        uint256 balBefore = address(this).balance;
        desk.sweepMargin(4);
        assertGt(address(this).balance, balBefore);
    }

    function testSweepMarginTooEarly() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(8, 50, 70, expiry, 1);
        vm.warp(expiry + 1);
        _push(90);
        desk.settle(8);
        vm.expectRevert(bytes("ITM"));
        desk.sweepMargin(8);
    }
}
