// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobParimutuel.sol";

contract BSPFuzz is Test {
    BlobParimutuel pm;
    address bettor = address(0xBEEF);
    
    // allow this contract to receive ether (rake)
    receive() external payable {}

    function setUp() public {
        pm = new BlobParimutuel(address(0));
    }

    function testFuzz(uint96 fee, uint96 betAmount) public {
        fee = uint96(bound(fee,1,200));
        betAmount = uint96(bound(betAmount,1e16,10 ether));
        pm = new BlobParimutuel(address(0));

        // Place HI bet
        vm.deal(bettor, betAmount);
        vm.prank(bettor);
        pm.betHi{value: betAmount}();

        // Place LO bet (ensure nonzero pool for both)
        uint96 loBet = betAmount; // or some fraction
        vm.deal(address(0xCAFE), loBet);
        vm.prank(address(0xCAFE));
        pm.betLo{value: loBet}();

        vm.warp(block.timestamp + 3600 + 12);
        // Mock the blobBaseFee oracle response
        vm.mockCall(
            address(0),
            abi.encodeWithSignature("blobBaseFee()"),
            abi.encode(fee)
        );

        pm.settle();

        // Destructure the round tuple
        (uint256 closeTs, uint256 hiPool, uint256 loPool, uint256 feeWei, uint256 thresholdGwei, uint256 settlePriceGwei) = pm.rounds(1);
        bool hiWin = fee >= thresholdGwei;
        uint256 winPool = hiWin ? hiPool : loPool;
        vm.assume(winPool > 0);

        vm.prank(hiWin ? bettor : address(0xCAFE));
        pm.claim(1);
    }
} 