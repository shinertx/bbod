// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobParimutuel.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

using ECDSA for bytes32;

contract WinnerlessParimutuel is Test {
    BlobParimutuel pm;
    BlobFeeOracle oracle;
    address bettor = address(0xBEEF);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;

    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        pm = new BlobParimutuel(address(oracle));
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
        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", fee, block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(fee, sigs);

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
} 