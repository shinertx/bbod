// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import "lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol";
import "./IBlobBaseFee.sol";
using MessageHashUtils for bytes32;

/**
 * @title BlobFeeOracle
 * @notice Simple 3-of-N push-oracle for the blob base-fee (denominated in gwei)
 *         Signers submit fee observations once per 12-second slot.  When the
 *         configured quorum is reached the oracle records the fee contained in
 *         the signed message (one of the submitted observations) as the
 *         canonical value for that slot.
 *
 *         To keep gas costs predictable the implementation deliberately avoids
 *         dynamic arrays in storage.  Instead, a bit-mask is used to keep track
 *         of which signers have already voted in a given slot.
 *
 *         The contract is self-contained and owner-less – the only privileged
 *         accounts are the signers that are specified at construction time.
 */
contract BlobFeeOracle is IBlobBaseFee, EIP712 {
    struct FeedMsg { uint256 fee; uint256 deadline; }
    bytes32 private constant FEED_TYPEHASH = keccak256("FeedMsg(uint256 fee,uint256 deadline)");
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

    /// @dev Track if a slot already finalised.
    mapping(uint256 => bool) public slotPushed;

    /// @dev Last canonical fee (gwei) that reached quorum.
    uint256 public lastFee;

    /// @dev Timestamp when `lastFee` was updated.
    uint256 public lastTs;

    /// @dev Address of the timelock contract.
    address public immutable timelock;

    /// @dev Boolean indicating whether the contract is paused.
    bool public paused;

    /// @dev Allow manual override if oracle is inactive for a long period.
    uint256 public constant OVERRIDE_DELAY = 7200; // slots (~1 day)

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _signers  Array of authorised signer addresses (max 256).
    /// @param _quorum   Required number of signatures to finalise a slot.
    constructor(address[] memory _signers, uint256 _quorum)
        EIP712("BlobFeeOracle", "1")
    {
        require(_signers.length > 0 && _signers.length <= 256, "bad signers");
        require(_quorum > 0 && _quorum <= _signers.length, "quorum");
        require(_quorum * 3 >= _signers.length * 2, "q<2/3");

        signers = _signers;
        minSigners = _quorum;
        for(uint256 i=0;i<_signers.length;i++){
            signerIndex[_signers[i]] = i;
            isSigner[_signers[i]] = true;
        }
        timelock = msg.sender; // deployer becomes timelock
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

    /// @notice Push a new fee observation using EIP-712 quorum signatures.
    function push(FeedMsg calldata m, bytes[] calldata sigs) external {
        require(!paused, "paused");
        require(block.timestamp <= m.deadline, "expired");
        require(m.fee < 10_000, "fee-out-of-range");
        if (lastFee != 0) {
            require(
                m.fee >= lastFee / 2 && m.fee <= lastFee * 2,
                "fee-unstable"
            );
        }
        require(sigs.length >= minSigners, "quorum");

        uint256 slot = block.timestamp / 12;
        require(!slotPushed[slot], "already-pushed");
        slotPushed[slot] = true;

        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(FEED_TYPEHASH, m.fee, m.deadline))
        );

        uint256 seen;
        for (uint256 i = 0; i < sigs.length; i++) {
            address s = ECDSA.recover(digest, sigs[i]);
            require(isSigner[s] && !jailed[s], "!signer");
            uint256 idx = signerIndex[s];
            uint256 flag = 1 << idx;
            require(seen & flag == 0, "dup");
            seen |= flag;
        }
        require(_popcount(seen) >= minSigners, "quorum");

        lastFee = m.fee;
        lastTs = block.timestamp;
        emit Pushed(m.fee);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               VIEW / PURE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBlobBaseFee
    function blobBaseFee() external view override returns (uint256) {
        return lastFee;
    }

    /// @notice Number of authorised signers.
    function signerCount() external view returns (uint256) {
        return signers.length;
    }

    /// @dev Count set bits using Brian Kernighan's algorithm.
    function _popcount(uint256 x) private pure returns (uint256 c) {
        while (x != 0) {
            x &= x - 1;
            unchecked { c++; }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                              GOVERNANCE UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    address[] private pendingSigners;
    uint256  private pendingMinSigners;
    uint256  private readyTs;
    uint256  public constant UPGRADE_DELAY = 48 hours;

    function proposeSigners(address[] calldata _new, uint256 _q) external {
        require(msg.sender == timelock, "!tl");
        require(_new.length > 0 && _new.length <= 256, "bad");
        require(_q>0 && _q<=_new.length, "q");
        require(_q * 3 >= _new.length * 2, "q<2/3");
        delete pendingSigners;
        for(uint i=0;i<_new.length;i++) pendingSigners.push(_new[i]);
        pendingMinSigners = _q;
        readyTs = block.timestamp + UPGRADE_DELAY;
    }

    function execUpgrade() external {
        require(msg.sender == timelock, "!tl");
        require(readyTs!=0 && block.timestamp>=readyTs, "too early");
        signers = pendingSigners;
        minSigners = pendingMinSigners;
        for(uint256 i=0;i<pendingSigners.length;i++){
            address s = pendingSigners[i];
            signerIndex[s] = i;
            isSigner[s] = true;
        }
        delete readyTs;
    }

    /// @notice Manually set the fee if signers are inactive for too long.
    /// @dev Allows timelock to unblock the system after ~1 day without pushes.
    function overrideFee(uint256 slot, uint256 feeGwei) external {
        require(msg.sender == timelock, "!tl");
        require(block.timestamp / 12 >= slot + OVERRIDE_DELAY, "active");
        require(!slotPushed[slot], "already-pushed");
        slotPushed[slot] = true;
        require(feeGwei < 10_000, "fee-out-of-range");
        lastFee = feeGwei;
        lastTs = block.timestamp;
        emit Pushed(feeGwei);
    }

    function pause(bool p) external { require(msg.sender==timelock, "!tl"); paused=p; }

    /*//////////////////////////////////////////////////////////////////////////
                                  SLASHING / JAILING
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Timelock can jail / unjail misbehaving signers (prevents voting).
    function jailSigner(address s, bool j) external {
        require(msg.sender == timelock, "!tl");
        require(isSigner[s], "unknown");
        jailed[s] = j;
    }
}
