// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";

contract OptionExpiryValidation is Test {
    BlobOptionDesk desk;
    function setUp() public {
        desk = new BlobOptionDesk(address(0));
    }

    function testBadExpiry() public {
        vm.expectRevert("too-soon");
        desk.create{value: 1 ether}(1, 50, 75, block.timestamp, 1);
    }
}
