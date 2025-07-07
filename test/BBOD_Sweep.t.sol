// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract BBODSweep is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    uint256 PK = 0xA11CE;
    address signer;

    function setUp() public {
        signer = vm.addr(PK);
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
    }

    bytes32 constant DOMAIN = keccak256(
        abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("BlobFeeOracle")),
            keccak256(bytes("1")),
            block.chainid,
            address(oracle)
        )
    );
    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    function _push(uint256 fee) internal {
        uint256 dl = block.timestamp + 30;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        BlobFeeOracle.FeedMsg[] memory msgs = new BlobFeeOracle.FeedMsg[](1);
        msgs[0] = BlobFeeOracle.FeedMsg({fee: fee, deadline: dl});
        oracle.push(msgs, sigs);
    }

    function testSweepMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(1, 100, 120, expiry, 1);
        vm.warp(expiry + 1);
        _push(90); // below strike => OTM
        desk.settle(1);
        vm.warp(expiry + desk.GRACE_PERIOD() + 1);
        uint256 balBefore = address(this).balance;
        desk.sweepMargin(1);
        assertEq(address(this).balance, balBefore + 1 ether);
    }
}
