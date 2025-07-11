// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";

contract OversellMaxSoldTest is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    address[] signers;
    address writer = address(this);

    function setUp() public {
        signers.push(address(this));
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function testCannotOversell() public {
        uint256 strike = 100;
        uint256 cap = 120;
        uint256 maxSold = 1;
        uint256 maxPay = (cap - strike) * 1 gwei * maxSold;
        desk.create{value: maxPay}(1, strike, cap, block.timestamp + 1 days, maxSold);

        // Buy the single allowed option
        uint256 prem = desk.premium(strike, block.timestamp + 1 days);
        desk.buy{value: prem}(1, 1);

        // Try to buy another one
        vm.expectRevert("sold-out");
        desk.buy{value: prem}(1, 1);
    }
}