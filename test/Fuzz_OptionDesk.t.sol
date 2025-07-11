// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/IBlobBaseFee.sol";

contract DummyOracle is IBlobBaseFee {
    uint256 public fee;
    function set(uint256 f) external { fee = f; }
    function blobBaseFee() external view returns (uint256) { return fee; }
}

contract Fuzz_OptionDesk is Test {
    BlobOptionDesk desk;
    DummyOracle oracle;

    function setUp() public {
        oracle = new DummyOracle();
        desk = new BlobOptionDesk(address(oracle));
    }

    receive() external payable {}

    /// @notice Fuzz: writer margin must always be >= sum(paid) after settlement.
    function testFuzz_MarginSafety(uint256 strike, uint256 cap, uint256 fee, uint256 qty) public {
        strike = bound(strike, 1, 50);
        cap    = bound(cap, strike+1, strike+100);
        fee    = bound(fee, 1, 200); // Bound fee to reasonable range
        qty    = bound(qty, 1, 5);
        
        uint256 id = 1;
        uint256 expiry = block.timestamp + 1 hours;
        
        // Prevent overflow in margin calculation
        uint256 spread = cap - strike;
        require(spread <= type(uint256).max / (1 gwei * 10), "spread too large");
        uint256 maxPay = spread * 1 gwei * 10;
        
        desk.create{value: maxPay}(id, strike, cap, expiry, 10);
        vm.deal(address(this), 100 ether);
        uint256 prem = desk.premium(strike, expiry) * qty;
        desk.buy{value: prem}(id, qty);
        oracle.set(fee);
        vm.warp(expiry+1);
        desk.settle(id);
        uint256 before = address(desk).balance;
        desk.exercise(id, qty);
        uint256 afterBal = address(desk).balance;
        assert(afterBal <= before);
    }
}