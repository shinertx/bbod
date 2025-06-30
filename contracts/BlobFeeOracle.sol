// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IBlobBaseFee.sol";

/**
 * @title BlobFeeOracle
 * @notice Simple 3-of-N push-oracle for the blob base-fee (denominated in gwei)
 *         Signers submit fee observations once per 12-second slot.  When the
 *         configured quorum is reached the contract stores the arithmetic mean
 *         of the submitted observations as the canonical fee for that slot.
 *
 *         To keep gas costs predictable the implementation deliberately avoids
 *         dynamic arrays in storage.  Instead, a bit-mask is used to keep track
 *         of which signers have already voted in a given slot.
 *
 *         The contract is self-contained and owner-less – the only privileged
 *         accounts are the signers that are specified at construction time.
 */
contract BlobFeeOracle is IBlobBaseFee {
    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted each time a new canonical fee is stored.
    /// @param feeGwei The blob base fee in gwei.
    event NewFee(uint256 feeGwei);

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Immutable list of authorised signers.
    address[] public signers;

    /// @dev Number of required signatures for a slot to be considered final.
    uint256 public immutable quorum; // e.g. 3-of-N

    /// @dev Last canonical fee (gwei) that reached quorum.
    uint256 public lastFee;

    /// @dev Timestamp when `lastFee` was updated.
    uint256 public lastTs;

    /// @dev Mapping slot => bit-mask of already cast votes.
    mapping(uint256 => uint256) private voteMask;

    /// @dev Mapping slot => running sum of fee observations.
    mapping(uint256 => uint256) private feeSum;

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _signers  Array of authorised signer addresses (max 256).
    /// @param _quorum   Required number of signatures to finalise a slot.
    constructor(address[] memory _signers, uint256 _quorum) {
        require(_signers.length > 0 && _signers.length <= 256, "bad signers");
        require(_quorum > 0 && _quorum <= _signers.length, "bad quorum");

        signers = _signers;
        quorum  = _quorum;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier onlySigner() {
        bool ok;
        for (uint256 i = 0; i < signers.length; i++) {
            if (msg.sender == signers[i]) {
                ok = true;
                break;
            }
        }
        require(ok, "!signer");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Push a new fee observation for the current 12-second slot.
    /// @param feeGwei Observed blob base fee in gwei (sanity-capped < 1000 gwei).
    function push(uint256 feeGwei) external onlySigner {
        require(feeGwei < 1_000, "sanity");

        uint256 slot = block.timestamp / 12; // 12-second slots – tolerate clock skew.

        // Derive index of signer in the array.  We iterate only once because the
        // signer set is expected to be small (<10).
        uint256 signerIdx;
        for (uint256 i = 0; i < signers.length; i++) {
            if (msg.sender == signers[i]) {
                signerIdx = i;
                break;
            }
        }

        // Ensure the signer has not already voted in this slot.
        uint256 mask = voteMask[slot];
        uint256 flag = 1 << signerIdx; // safe because signerIdx < 256
        require(mask & flag == 0, "dup");

        // Update vote bit-mask and cumulative sum.
        voteMask[slot] = mask | flag;
        feeSum[slot] += feeGwei;

        // Finalise once quorum reached.
        uint256 count = _popcount(voteMask[slot]);
        if (count >= quorum) {
            lastFee = feeSum[slot] / count; // arithmetic mean in gwei
            lastTs  = block.timestamp;
            emit NewFee(lastFee);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               VIEW / PURE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlobBaseFee
    function blobBaseFee() external view override returns (uint256) {
        return lastFee;
    }

    /// @dev Count set bits using Brian Kernighan's algorithm.
    function _popcount(uint256 x) private pure returns (uint256 c) {
        while (x != 0) {
            x &= x - 1;
            unchecked { c++; }
        }
    }
} 