// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobParimutuel.sol";

contract BSPFuzz is Test {
    BlobParimutuel pm;
    address bettor = address(0xBEEF);
    
    function setUp() public { 
        pm = new BlobParimutuel(); 
    }

    function testFuzz(uint96 fee, uint96 betAmount) public {
        fee = uint96(bound(fee,0,200));
        betAmount = uint96(bound(betAmount,1e16,10 ether));
        pm = new BlobParimutuel();

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
        // cheat the fee into storage
        vm.store(address(pm), bytes32(uint256(2)), bytes32(uint256(fee)));

        pm.settle();

        // Destructure the round tuple
        (uint256 closeTs, uint256 hiPool, uint256 loPool, uint256 feeWei, uint256 thresholdGwei) = pm.rounds(1);
        bool hiWin = fee >= thresholdGwei;
        uint256 winPool = hiWin ? hiPool : loPool;
        vm.assume(winPool > 0);

        vm.prank(hiWin ? bettor : address(0xCAFE));
        pm.claim(1);
    }
} 