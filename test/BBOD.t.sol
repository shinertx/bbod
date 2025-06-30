// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";

contract BBODFuzz is Test {
    BlobOptionDesk desk;
    address buyer = address(0xBEEF);
    function setUp() public { desk = new BlobOptionDesk(); }

    function testFuzz(uint96 fee,uint96 strike) public {
        fee   = uint96(bound(fee,0,200));
        strike= uint96(bound(strike,0,fee));
        vm.prank(address(this));
        desk.create{value: 10 ether}(1,strike,block.timestamp+1,100);
        uint prem = desk.premium(strike, block.timestamp+1);
        vm.deal(buyer, prem);
        vm.prank(buyer);
        desk.buy{value: prem}(1,1);
        vm.warp(block.timestamp+2);
        vm.store(address(desk),bytes32(uint256(2)),bytes32(uint256(fee)));
        desk.settle(1);
        vm.prank(buyer);
        desk.exercise(1);
    }
} 