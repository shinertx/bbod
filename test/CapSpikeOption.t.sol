// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";

contract CapSpikeOptionTest is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    address writer = address(this);
    address[] signers;

    function setUp() public {
        signers.push(address(this));
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function testCapSpike() public {
        uint256 strike = 100;
        uint256 cap = 120;
        uint256 maxSold = 10;
        uint256 maxPay = (cap - strike) * 1 gwei * maxSold;

        // writer create series with margin
        desk.create{value: maxPay}(1, strike, cap, block.timestamp + 1, maxSold);

        // warp to expiry+1 and push fee above cap
        vm.warp(block.timestamp + 2);
        oracle.push(200); // fee higher than cap

        desk.settle(1);
        (,,, , uint256 payWei,,) = desk.series(1);
        assertEq(payWei, (cap - strike) * 1 gwei);
    }
} 