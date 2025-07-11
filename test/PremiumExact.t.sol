// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";

contract PremiumExact is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;

    function setUp() public {
        address[] memory signers = new address[](1);
        signers[0] = address(0x1);
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
        desk.create{value: 1 ether}(1, 50, 75, block.timestamp + 1 hours, 1);
    }

    function testRejectUnderpay() public {
        uint256 p = desk.premium(50, block.timestamp + 1 hours);
        vm.expectRevert("bad-premium");
        desk.buy{value: p - 1}(1, 1);
    }

    function testRejectOverpay() public {
        uint256 p = desk.premium(50, block.timestamp + 1 hours);
        vm.expectRevert("bad-premium");
        desk.buy{value: p + 1}(1, 1);
    }
}
