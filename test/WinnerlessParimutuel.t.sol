// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobParimutuel.sol";
import "../contracts/BlobFeeOracle.sol";

contract WinnerlessParimutuel is Test {
    BlobParimutuel pm;
    BlobFeeOracle oracle;
    address bettor = address(0xBEEF);
    address[] signers;

    receive() external payable {}

    function setUp() public {
        signers.push(address(this));
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

        // push oracle fee lower than threshold so HI loses (makes winPool=0)
        vm.prank(address(this));
        oracle.push(1);

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