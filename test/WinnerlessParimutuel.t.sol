// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobParimutuel.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract WinnerlessParimutuel is Test {
    BlobParimutuel pm;
    BlobFeeOracle oracle;
    address bettor = address(0xBEEF);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;
    bytes32 DOMAIN;
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        pm = new BlobParimutuel(address(oracle));
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

    function testWinnerlessRefund() public {
        uint256 stake = 1 ether;
        vm.deal(bettor, stake);

        // commit only on HI side to force winner-less round
        vm.prank(bettor);
        pm.betHi{value: stake}();

        // warp past close+grief guard
        uint256 close = _getClose();
        vm.warp(close + 13);

        // produce signature for fee push
        uint256 fee = 1;
        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl}), sigs);

        pm.settle();

        // bettor balance before claim
        uint256 balBefore = bettor.balance;

        vm.prank(bettor);
        pm.claim(1);

        uint256 balAfter = bettor.balance;
        // refund should equal the full stake (no rake)
        assertEq(balAfter - balBefore, stake);
    }

    function _getClose() internal view returns(uint256 close){
        (close,,,,,) = pm.rounds(1);
    }

    function testThresholdLock() public {
        vm.expectRevert("bet yet?");
        pm.setThreshold(80);

        vm.prank(bettor);
        pm.betHi{value: 1 ether}();
        pm.setThreshold(80);

        uint256 close = _getClose();
        vm.warp(close + 13);
        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, uint256(50), dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: 50, deadline: dl}), sigs);
        pm.settle();
        (,,,, uint256 thr,) = pm.rounds(2);
        assertEq(thr, 80);
    }
}
