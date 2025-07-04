// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract BBODFuzz is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    address buyer = address(0xBEEF);
    address[] signers;
    uint256 private PK = 0xA11CE;
    address private signer;

    // allow this contract to receive ETH refunds
    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    function testFuzz_Exercise(uint96 fee, uint96 strike) public {
        // constrain inputs
        fee = uint96(bound(fee, 0, 200));
        strike = uint96(bound(strike, 0, 199));

        // create series
        uint256 cap = strike + 50;
        vm.prank(address(this));
        desk.create{value: 10 ether}(1, strike, cap, block.timestamp + 1 hours, 100);

        // buy option
        uint256 prem = desk.premium(strike, block.timestamp + 1 hours);
        vm.deal(buyer, prem);
        vm.prank(buyer);
        desk.buy{value: prem}(1, 1);

        // time passes + oracle push
        vm.warp(block.timestamp + 1 hours + 1);
        // sign and push fee
        bytes32 digest = keccak256(abi.encodePacked("BLOB_FEE", uint256(fee), block.timestamp/12));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest.toEthSignedMessageHash());
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(fee, sigs);

        // settle
        desk.settle(1);

        if (fee > strike) {
            vm.prank(buyer);
            desk.exercise(1);
        }
    }
} 