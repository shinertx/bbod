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
        fee = uint96(bound(fee, 0, 200));
        betAmount = uint96(bound(betAmount, 0.01 ether, 10 ether));
        
        vm.deal(bettor, betAmount);
        vm.prank(bettor);
        pm.betHi{value: betAmount}();
        
        vm.warp(block.timestamp + 3600 + 12);
        
        // Mock the blobBaseFee call
        vm.mockCall(
            address(0), // zero address
            abi.encodeWithSignature("blobBaseFee()"),
            abi.encode(fee)
        );
        
        pm.settle();
        
        vm.prank(bettor);
        pm.claim(1);
    }
} 