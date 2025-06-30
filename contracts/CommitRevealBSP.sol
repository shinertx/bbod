// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CommitRevealBSP
 * @notice Trust-less parimutuel betting market on the blob base-fee.  Uses a
 *         commit-reveal scheme so that bettors cannot copy each other's bets in
 *         the final blocks before close.  Non-revealed tickets can be refunded
 *         (minus 1% grief-prevention fee) after a 1-hour grace window.
 */
contract CommitRevealBSP is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////////////////
                                     DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    enum Side { Hi, Lo }

    struct Ticket {
        bytes32 commit;
        uint256 amount;
    }

    struct Round {
        uint256 openTs;
        uint256 closeTs;
        uint256 revealTs;
        uint256 hiPool;
        uint256 loPool;
        uint256 rake;
        uint256 thresholdGwei;
        uint256 feeResult; // oracle fee for the round (gwei)
        bool settled;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event Commit(uint256 indexed round, address indexed user, uint256 amount);
    event Reveal(uint256 indexed round, address indexed user, Side side, uint256 amount);
    event Settled(uint256 indexed round, uint256 feeGwei, uint256 rakeWei);
    event Payout(uint256 indexed round, address indexed user, uint256 amount);
    event Refund(uint256 indexed round, address indexed user, uint256 amount);
    event NewRound(uint256 indexed round, uint256 closeTs, uint256 revealTs, uint256 thresholdGwei);

    /*//////////////////////////////////////////////////////////////////////////
                                      STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 public cur;
    address public immutable owner;
    IBlobBaseFee public immutable F;

    uint16 public constant RAKE_BP = 500; // 5%
    uint256 public constant GRACE_NONREVEAL = 15 minutes;

    mapping(uint256 => mapping(address => Ticket)) public tickets; // round -> user -> ticket
    mapping(uint256 => Round) public rounds;                       // round -> round data

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address oracle) {
        owner = msg.sender;
        F = IBlobBaseFee(oracle);
        _open(25); // bootstrap with default 25 gwei threshold
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "!own");
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   BETTING FLOW
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Commit hash = keccak256(abi.encodePacked(msg.sender, side, salt)).
    function commit(bytes32 h) external payable {
        Round storage R = rounds[cur];
        require(block.timestamp < R.closeTs, "closed");
        require(tickets[cur][msg.sender].commit == 0, "dup");

        tickets[cur][msg.sender] = Ticket({commit: h, amount: msg.value});
        emit Commit(cur, msg.sender, msg.value);
    }

    /// @notice Reveal side & salt during the reveal window.
    function reveal(Side side, bytes32 salt) external {
        Round storage R = rounds[cur];
        require(block.timestamp >= R.closeTs && block.timestamp < R.revealTs, "!reveal");

        Ticket storage T = tickets[cur][msg.sender];
        require(T.commit == keccak256(abi.encodePacked(msg.sender, side, salt)), "bad");

        if (side == Side.Hi) {
            R.hiPool += T.amount;
        } else {
            R.loPool += T.amount;
        }

        T.commit = bytes32(0); // mark as revealed
        emit Reveal(cur, msg.sender, side, T.amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Anyone may call once the reveal window has elapsed.
    function settle() external nonReentrant {
        Round storage R = rounds[cur];
        require(block.timestamp >= R.revealTs, "too early");
        require(!R.settled, "done");

        uint256 feeGwei = F.blobBaseFee();
        R.feeResult = feeGwei;
        R.settled = true;

        uint256 gross = R.hiPool + R.loPool;

        // Winner-less rescue: if everyone is on one side we skip rake and allow refunds.
        if (R.hiPool == 0 || R.loPool == 0) {
            R.rake = 0;
            emit Settled(cur, feeGwei, 0);
            _open(R.thresholdGwei);
            return; // early exit – claim() will refund bettors
        }

        uint256 rakeAmount = gross * RAKE_BP / 10_000;
        R.rake = rakeAmount;
        payable(owner).transfer(rakeAmount);

        emit Settled(cur, feeGwei, rakeAmount);

        _open(R.thresholdGwei); // open next round with same threshold
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 POST-SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    function claim(uint256 id, Side side, bytes32 salt) external nonReentrant {
        Round storage R = rounds[id];
        require(R.settled, "unsettled");

        Ticket storage T = tickets[id][msg.sender];

        bool oneSided = (R.hiPool == 0 || R.loPool == 0);

        if (T.commit == 0) {
            // Revealed path
            if (oneSided) {
                // round has no winners – refund
                uint256 refund = T.amount * 995 / 1000;
                tickets[id][msg.sender].amount = 0;
                payable(msg.sender).transfer(refund);
                emit Refund(id, msg.sender, refund);
            } else {
                _payout(id, msg.sender, side, salt);
            }
        } else {
            // Non-revealed ticket – allow refund after grace
            require(block.timestamp > R.revealTs + GRACE_NONREVEAL, "grace");
            uint256 refund = T.amount * 95 / 100;
            T.amount = 0;
            T.commit = bytes32(0);
            payable(msg.sender).transfer(refund);
            emit Refund(id, msg.sender, refund);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _payout(uint256 id, address who, Side side, bytes32 /*salt*/ ) internal {
        Round storage R = rounds[id];
        bool hiWin = R.feeResult >= R.thresholdGwei;
        bool win = (hiWin && side == Side.Hi) || (!hiWin && side == Side.Lo);
        require(win, "lose");

        uint256 poolWin = hiWin ? R.hiPool : R.loPool;
        uint256 total = R.hiPool + R.loPool - R.rake;

        uint256 share = tickets[id][who].amount;
        require(share > 0, "none");
        tickets[id][who].amount = 0;

        uint256 pay = (share * total) / poolWin;
        require(pay > 0, "dust");
        payable(who).transfer(pay);
        emit Payout(id, who, pay);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Owner may adjust threshold for *next* round.
    function setNextThreshold(uint256 thr) external onlyOwner {
        rounds[cur].thresholdGwei = thr;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   INTERNAL
    //////////////////////////////////////////////////////////////////////////*/

    function _open(uint256 thr) internal {
        cur += 1;
        rounds[cur] = Round({
            openTs: block.timestamp,
            closeTs: block.timestamp + 300,   // 5-minute commit phase
            revealTs: block.timestamp + 600,  // 5-minute reveal phase
            hiPool: 0,
            loPool: 0,
            rake: 0,
            thresholdGwei: thr,
            feeResult: 0,
            settled: false
        });
        emit NewRound(cur, block.timestamp + 300, block.timestamp + 600, thr);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 RECEIVE ETHER
    //////////////////////////////////////////////////////////////////////////*/

    receive() external payable {}
} 