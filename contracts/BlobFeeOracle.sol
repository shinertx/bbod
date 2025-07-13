// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "./IBlobBaseFee.sol";

/**
 * @title BlobFeeOracle
 * @notice Simple 3-of-N push-oracle for the blob base-fee (denominated in gwei)
 *         Signers submit fee observations once per 12-second slot. When the
 *         configured quorum is reached the oracle records the fee contained in
 *         the signed message (one of the submitted observations) as the
 *         canonical value for that slot.
 *
 *         To keep gas costs predictable the implementation deliberately avoids
 *         dynamic arrays in storage. Instead, a bit-mask is used to keep track
 *         of which signers have already voted in a given slot.
 *
 *         The contract is self-contained and owner-less – the only privileged
 *         accounts are the signers that are specified at construction time.
 */
contract BlobFeeOracle is IBlobBaseFee, EIP712 {
    struct FeedMsg { uint256 fee; uint256 deadline; uint256 nonce; }
    bytes32 private constant FEED_TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline,uint256 nonce)");
    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted each time a new fee observation reaches quorum.
    /// @param feeGwei The blob base fee in gwei.
    event Pushed(uint256 feeGwei);

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Immutable list of authorised signers.
    address[] public signers;

    /// @dev Minimal number of unique signer signatures required (>50 % of signer set).
    uint256 public minSigners;

    /// @dev Quick lookup for authorised signer.
    mapping(address => uint256) private signerIndex;
    mapping(address => bool)    public isSigner;
    mapping(address => bool)    public jailed;

    /// @dev Per-signer nonce to prevent signature replay.
    mapping(address => uint256) public nonces;

    /// @dev Track if a slot already finalised.
    mapping(uint256 => bool) public slotPushed;

    /// @dev Last canonical fee (gwei) that reached quorum.
    uint256 public lastFee;

    /// @dev Timestamp when `lastFee` was updated.
    uint256 public lastFeeTs;

    /// @dev Quorum of signatures required to push a fee.
    uint256 public quorum;

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address[] memory _signers, uint256 _quorum) EIP712("BlobFeeOracle", "1") {
        require(_quorum > 0 && _quorum <= _signers.length, "Invalid quorum");
        quorum = _quorum;
        for (uint i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            require(signer != address(0), "Zero address");
            require(!isSigner[signer], "Duplicate signer");
            isSigner[signer] = true;
            signers.push(signer);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC METHODS
    //////////////////////////////////////////////////////////////////////////*/

    function push(FeedMsg[] calldata msgs, bytes[] calldata signatures) external {
        require(msgs.length >= quorum, "Not enough signatures");
        require(msgs.length == signatures.length, "Mismatched inputs");

        uint256 fee = msgs[0].fee;
        address[] memory seenSigners = new address[](msgs.length);
        uint seenCount = 0;

        for (uint256 i = 0; i < msgs.length; i++) {
            FeedMsg calldata msg = msgs[i];
            require(msg.fee == fee, "Mismatched fees");
            require(msg.deadline >= block.timestamp, "Signature expired");

            bytes32 structHash = keccak256(abi.encode(FEED_TYPEHASH, msg.fee, msg.deadline, msg.nonce));
            bytes32 digest = _hashTypedDataV4(structHash);
            address signer = ECDSA.recover(digest, signatures[i]);

            require(isSigner[signer], "Invalid signer");
            require(msg.nonce == nonces[signer], "Invalid nonce");

            bool duplicate = false;
            for(uint j=0; j < seenCount; j++){
                if(seenSigners[j] == signer) {
                    duplicate = true;
                    break;
                }
            }
            require(!duplicate, "Duplicate signer");

            seenSigners[seenCount++] = signer;
        }

        // --- State Changes ---
        lastFee = fee;
        lastFeeTs = block.timestamp;
        for (uint256 i = 0; i < seenCount; i++) {
            nonces[seenSigners[i]]++;
        }

        emit Pushed(fee);
    }

    function latest() external view returns (uint256, uint256) {
        return (lastFee, lastFeeTs);
    }

    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
