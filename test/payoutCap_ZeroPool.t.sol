// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobParimutuel.sol";

contract PayoutCap_ZeroPool_Test is Test {
    BlobOptionDesk desk;
    BlobParimutuel pm;
    address oracle = address(0xABCD);

    receive() external payable {}

    function setUp() public {
        desk = new BlobOptionDesk(oracle);
        pm   = new BlobParimutuel(oracle);
    }

    function testPayoutCapped() public {
        // Writer sells 1 option with only 1 ether margin (cap-strike=100 gwei) so max payout is 1 ether
        uint256 strike = 10; // gwei
        uint256 cap = 20;    // gwei (delta 10 gwei => 0.00000001 ether per option)
        uint256 maxSold = 1;
        uint256 margin = 1 ether;
        desk.create{value: margin}(1, strike, cap, block.timestamp + 1, maxSold);

        uint256 prem = desk.premium(strike, block.timestamp + 1);
        address trader = address(0xB0B);
        vm.deal(trader, prem);
        vm.prank(trader);
        desk.buy{value: prem}(1, 1);

        // warp beyond expiry
        vm.warp(block.timestamp + 2);
        // Mock oracle to huge fee so rawPay would exceed margin
        vm.mockCall(oracle, abi.encodeWithSignature("blobBaseFee()"), abi.encode(300));

        desk.settle(1);

        // Exercise should succeed and pay at most 1 ether
        vm.prank(trader);
        desk.exercise(1);
    }

    function testZeroPoolRefund() public {
        uint256 bet = 1 ether;
        address bettor = address(0xCAFE);
        vm.deal(bettor, bet);
        vm.prank(bettor);
        pm.betHi{value: bet}(); // only hi side has stake

        // advance time to settle eligible
        vm.warp(block.timestamp + 3600 + 12);
        vm.mockCall(oracle, abi.encodeWithSignature("blobBaseFee()"), abi.encode(50));
        pm.settle();

        // Claim refund
        vm.prank(bettor);
        pm.claim(1);
    }
} 