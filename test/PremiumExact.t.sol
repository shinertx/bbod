// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";

contract PremiumExact is Test {
    BlobOptionDesk desk;

    function setUp() public {
        desk = new BlobOptionDesk(address(0));
        desk.create{value: 1 ether}(1, 50, 75, block.timestamp + 1 hours, 1);
    }

    function testRejectUnderpay() public {
        uint256 p = desk.premium(50, block.timestamp + 1 hours);
        vm.expectRevert("!prem");
        desk.buy{value: p - 1}(1, 1);
    }

    function testRejectOverpay() public {
        uint256 p = desk.premium(50, block.timestamp + 1 hours);
        vm.expectRevert("!prem");
        desk.buy{value: p + 1}(1, 1);
    }
}
