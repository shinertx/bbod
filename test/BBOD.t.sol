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
    address private writer;

    // allow this contract to receive ETH refunds
    receive() external payable {}

    function setUp() public {
        signer = vm.addr(PK);
        signers.push(signer);
        oracle = new BlobFeeOracle(signers, 1);
        writer = msg.sender;
        desk = new BlobOptionDesk(address(oracle));
        vm.deal(address(this), 100 ether);
    }

    function testFuzz_Exercise(uint96 fee, uint96 strike) public {
        // constrain inputs
        fee = uint96(bound(fee, 0, 200));
        strike = uint96(bound(strike, 1, 199)); // strike cannot be 0

        // create series
        uint256 cap = strike + 50;
        uint256 expiry = block.timestamp + 1 hours;
        vm.prank(writer);
        desk.create{value: 10 ether}(1, strike, cap, expiry, 100);

        // buy option
        uint256 prem = desk.premium(strike, expiry);
        vm.deal(buyer, prem);
        vm.prank(buyer);
        desk.buy{value: prem}(1, 1);

        // time passes + oracle push
        vm.warp(expiry + 1);
        // sign and push fee
        uint256 dl = block.timestamp + 30;
        bytes32 domain = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("BlobFeeOracle")),
            keccak256(bytes("1")),
            block.chainid,
            address(oracle)
        ));
        bytes32 structHash = keccak256(abi.encode(keccak256("FeedMsg(uint256 fee,uint256 deadline)"), uint256(fee), dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(domain, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl}), sigs);

        // exercise
        desk.settle(1);
        if (fee > strike) {
            vm.prank(buyer);
            desk.exercise(1, 1);
        }

        // settle
        vm.warp(expiry + 1 hours + 1);
        vm.prank(writer);
        desk.withdrawMargin(1);
    }
}