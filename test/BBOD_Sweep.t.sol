// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
using ECDSA for bytes32;
using MessageHashUtils for bytes32;

contract BBODWithdraw is Test {
    BlobOptionDesk desk;
    BlobFeeOracle oracle;
    uint256 PK = 0xA11CE;
    address signer;
    bytes32 DOMAIN;

    function setUp() public {
        signer = vm.addr(PK);
        address[] memory signers = new address[](1);
        signers[0] = signer;
        oracle = new BlobFeeOracle(signers, 1);
        desk = new BlobOptionDesk(address(oracle));
        DOMAIN = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("BlobFeeOracle")),
                keccak256(bytes("1")),
                block.chainid,
                address(oracle)
            )
        );
    }

    // Allow the test contract to receive ETH
    receive() external payable {}

    bytes32 constant TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");

    function _push(uint256 fee) internal {
        uint256 dl = block.timestamp + 30;
        uint256 nonce = 0;
        bytes32 structHash = keccak256(abi.encode(TYPEHASH, fee, dl, nonce));
        bytes32 digest = MessageHashUtils.toTypedDataHash(DOMAIN, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = abi.encodePacked(r, s, v);
        oracle.push(BlobFeeOracle.FeedMsg({fee: fee, deadline: dl, nonce: nonce}), sigs);
    }

    function testWithdrawMarginOTM() public {
        uint256 expiry = block.timestamp + 1 hours;
        desk.create{value: 1 ether}(1, 100, 120, expiry, 1);
        vm.warp(expiry + 1 hours + 1); // Settle can only be called after the exercise grace period
        _push(90); // below strike => OTM
        desk.settle(1);
        uint256 balBefore = address(this).balance;
        desk.withdrawMargin(1);
        uint256 bounty = 1 ether / 100; // SETTLE_BOUNTY_BP is 100, so 1%
        assertEq(address(this).balance, balBefore + 1 ether - bounty);
    }
}
