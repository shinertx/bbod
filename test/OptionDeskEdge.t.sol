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

    function setUp() public {
        signer = vm.addr(PK);
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function testBuyCutoff() public {
        uint256 expiry = block.timestamp + 1000;
        desk.create{value: 1 ether}(1, 50, 60, expiry, 1);
        vm.warp(expiry - 1);
        uint256 p = desk.premium(50, expiry);
        vm.deal(buyer, p);
        vm.prank(buyer);
        vm.expectRevert("too-late-to-buy");
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

    function _push(uint256 fee) internal {
        bytes32 h = keccak256(abi.encodePacked("BLOB_FEE", fee, block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, h.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(fee, sigs);
    }

    function testWithdrawMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(3, 100, 120, expiry, 1);
        vm.warp(expiry + 1);
        _push(50);
        desk.settle(3);
        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(3);
        assertEq(address(this).balance, balBefore + 1 ether);
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
        uint256 balBefore = address(this).balance;
        desk.sweepMargin(4);
        assertGt(address(this).balance, balBefore);
    }
}
