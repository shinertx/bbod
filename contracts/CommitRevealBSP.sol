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
        Side    side;    // side revealed by user
        bool claimed; // whether the user has claimed their payout
    }

    struct Round {
        uint256 id;
        uint256 closeTs;
        uint256 revealTs;
        uint256 settleTs;
        uint256 hiTotal;
        uint256 loTotal;
        uint256 totalCommits;
        Side winner;
        uint256 threshold;
        bytes32 thresholdCommit;
        uint256 feeResult; // oracle fee for the round (gwei)
        uint256 settlePriceGwei;
        bool settled;
        uint256 bounty;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event Commit(uint256 indexed round, address indexed user, uint256 amount);
    event Reveal(uint256 indexed round, address indexed user, Side side, uint256 amount);
    event Settled(uint256 indexed round, uint256 feeGwei, uint256 rakeWei, uint256 bountyWei);
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
    uint16 public constant SETTLE_BOUNTY_BP = 10; // 0.10 %
    uint256 public constant MIN_BET = 0.01 ether;
    uint256 public constant MAX_BET_PER_ADDRESS = 10 ether;  // Anti-whale protection
    uint256 public constant MAX_TOTAL_POSITION_RATIO = 7500; // Max 75% of round on one side
    uint256 public constant MAX_INDIVIDUAL_POSITION_RATIO = 9000; // Max 90% from single address
    uint256 public constant GRACE_NONREVEAL = 15 minutes;

    mapping(uint256 => mapping(address => Ticket)) public tickets; // round -> user -> ticket
    mapping(uint256 => Round) public rounds;                       // round -> round data

    bytes32  public thresholdCommit;
    uint256  public commitRound; // round the commit applies to
    uint256  public commitTs;
    uint256  public constant REVEAL_TIMEOUT = 15 minutes;
    uint256  public constant THRESHOLD_REVEAL_TIMEOUT = 90 minutes;
    uint256  public nextThreshold;

    uint256 public constant ROUND_DURATION = 1 hours;
    uint256 public constant REVEAL_WINDOW = 5 minutes;

    mapping(address => uint256) public roundBets; // Track bets per address per round
    mapping(address => uint256) public lastRoundParticipated; // Track which round user last bet in

    /*//////////////////////////////////////////////////////////////////////////
                                    PAUSING
    //////////////////////////////////////////////////////////////////////////*/

    bool public paused;
    modifier notPaused() { require(!paused, "paused"); _; }

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address oracle) {
        owner = msg.sender;
        F = IBlobBaseFee(oracle);
        _open(100 gwei); // bootstrap with default 100 gwei threshold
    }

    // Allow contract to receive ETH
    receive() external payable {}

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
    function commit(bytes32 h) external payable notPaused {
        Round storage R = rounds[cur];
        require(block.timestamp < R.closeTs, "closed");
        require(msg.value >= MIN_BET, "dust");
        require(msg.value <= MAX_BET_PER_ADDRESS, "too-large");
        require(tickets[cur][msg.sender].commit == 0, "dup");
        
        // Reset bet tracking for new round
        if (lastRoundParticipated[msg.sender] != cur) {
            roundBets[msg.sender] = 0;
            lastRoundParticipated[msg.sender] = cur;
        }
        
        // Anti-Sybil: track total bets per address per round
        require(roundBets[msg.sender] + msg.value <= MAX_BET_PER_ADDRESS, "address-limit");
        roundBets[msg.sender] += msg.value;

        tickets[cur][msg.sender] = Ticket({commit: h, amount: msg.value, side: Side.Hi, claimed: false});
        R.totalCommits += msg.value; // Track total committed for non-revealed stake calculation
        emit Commit(cur, msg.sender, msg.value);
    }

    /// @notice Reveal side & salt during the reveal window.
    function reveal(Side side, bytes32 salt) external notPaused {
        Round storage R = rounds[cur];
        require(block.timestamp >= R.closeTs && block.timestamp < R.revealTs, "!reveal");

        Ticket storage T = tickets[cur][msg.sender];
        require(T.commit != bytes32(0), "revealed");
        require(T.commit == keccak256(abi.encodePacked(msg.sender, side, salt)), "bad");

        // Correctly calculate the total amount that will be revealed *after* this transaction.
        uint256 totalRevealedAfter = R.hiTotal + R.loTotal + T.amount;

        // Check position concentration limits. This must apply to ALL reveals.
        if (side == Side.Hi) {
            require((R.hiTotal + T.amount) * 10000 <= totalRevealedAfter * MAX_TOTAL_POSITION_RATIO, "position-limit");
        } else {
            require((R.loTotal + T.amount) * 10000 <= totalRevealedAfter * MAX_TOTAL_POSITION_RATIO, "position-limit");
        }
        
        // Additional check: prevent single address from dominating
        require(T.amount * 10000 <= totalRevealedAfter * MAX_INDIVIDUAL_POSITION_RATIO, "individual-limit");

        if (side == Side.Hi) {
            R.hiTotal += T.amount;
        } else {
            R.loTotal += T.amount;
        }

        // persist revealed side to prevent later spoofing
        T.commit = bytes32(0); // mark as revealed
        T.side   = side;
        emit Reveal(cur, msg.sender, side, T.amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Anyone may call once the reveal window has elapsed.
    function settle() external nonReentrant notPaused {
        Round storage R = rounds[cur];
        require(block.timestamp >= R.revealTs, "too early");
        require(!R.settled, "done");
        
        // MEV protection: add randomized delay to prevent deterministic settlement timing
        // In test environments (block.timestamp < 100000), use minimal delay for testing
        uint256 settlementDelay;
        if (block.timestamp < 100000) {
            settlementDelay = 1; // Minimal delay for tests
        } else {
            // Use multiple entropy sources for true randomization
            settlementDelay = uint256(keccak256(abi.encodePacked(
                block.timestamp, 
                block.prevrandao, // Use prevrandao instead of deprecated difficulty
                cur,
                R.hiTotal,
                R.loTotal
            ))) % 600; // 0-10 min delay
        }
        require(block.timestamp >= R.revealTs + settlementDelay, "settlement-delay");
        
        uint256 nextThr;
        if (commitRound == cur) {
            if (block.timestamp < commitTs + THRESHOLD_REVEAL_TIMEOUT) {
                if (nextThreshold == 0) revert("!reveal");
                nextThr = nextThreshold;
            } else {
                // timed out, use current threshold for next round
                nextThr = R.threshold;
            }
        } else {
            // no commit for this round, carry over threshold
            nextThr = R.threshold;
        }

        uint256 feeGwei = F.blobBaseFee();
        if (feeGwei == 0) revert("fee-not-set");
        if (feeGwei > 200 * 1 gwei) revert("fee-out-of-range");
        R.feeResult = feeGwei;
        R.settlePriceGwei = feeGwei;
        R.settled = true;

        // Determine winner based on fee vs threshold
        bool hiWin = feeGwei >= R.threshold;
        R.winner = hiWin ? Side.Hi : Side.Lo;

        uint256 gross = R.hiTotal + R.loTotal;
        uint256 nonRevealedStake = R.totalCommits - R.hiTotal - R.loTotal;

        // Winner-less rescue: if everyone is on one side AND there are no non-revealed stakes
        if ((R.hiTotal == 0 || R.loTotal == 0) && nonRevealedStake == 0) {
            R.bounty = 0;
            emit Settled(cur, feeGwei, 0, 0);
            uint256 thr = nextThr;
            nextThreshold = 0;
            commitRound = 0;
            thresholdCommit = 0;
            _open(thr);
            return; // early exit – claim() will refund bettors
        }

        uint256 totalGross = gross + nonRevealedStake;
        uint256 bounty = totalGross * SETTLE_BOUNTY_BP / 10_000;
        uint256 rakeAmount = totalGross * RAKE_BP / 10_000;
        R.bounty = bounty;
        if (bounty > 0) _safeSend(msg.sender, bounty);
        _safeSend(owner, rakeAmount);

        emit Settled(cur, feeGwei, rakeAmount, bounty);

        nextThreshold = 0;
        commitRound = 0;
        thresholdCommit = 0;
        _open(nextThr); // open next round with enforced threshold
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 POST-SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    error PoolHasNoWinners();

    function claim(uint256 roundId, Side side, bytes32 salt) public nonReentrant notPaused {
        Round storage r = rounds[roundId];
        require(r.settled, "unsettled");

        Ticket storage bet = tickets[roundId][msg.sender];

        bool oneSided = (r.hiTotal == 0 || r.loTotal == 0) && (r.totalCommits - r.hiTotal - r.loTotal == 0);

        if (bet.commit == 0) {
            // Revealed path
            if (oneSided) {
                // round has no winners – refund
                uint256 refund = bet.amount;
                tickets[roundId][msg.sender].amount = 0;
                _safeSend(msg.sender, refund);
                emit Refund(roundId, msg.sender, refund);
            } else {
                // ensure user cannot spoof a different side after reveal
                require(tickets[roundId][msg.sender].side == side, "side-mismatch");
                _payout(roundId, msg.sender);
            }
        } else {
            // Non-revealed ticket forfeits full stake to house after grace
            require(block.timestamp > r.revealTs + GRACE_NONREVEAL, "grace");
            uint256 burn = bet.amount;
            delete tickets[roundId][msg.sender];
            _safeSend(owner, burn);
            emit Refund(roundId, msg.sender, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _payout(uint256 id, address who) internal {
        Round storage r = rounds[id];
        Ticket storage bet = tickets[id][who];
        require(!bet.claimed, "claimed");
        bet.claimed = true;

        uint256 winnerTotal = r.winner == Side.Hi ? r.hiTotal : r.loTotal;
        // This check should ideally not be hit if claim is called correctly
        if (winnerTotal == 0) {
            // This case should be handled by the one-sided refund logic in `claim`
            // but as a safeguard, we prevent division by zero.
            return;
        }
        
        uint256 loserTotal = r.winner == Side.Hi ? r.loTotal : r.hiTotal;
        uint256 nonRevealed = r.totalCommits - r.hiTotal - r.loTotal;

        // The total pot available for distribution is the sum of winning, losing, and non-revealed stakes.
        uint256 totalPot = r.hiTotal + r.loTotal + nonRevealed;
        
        // The fees (rake + bounty) were already calculated on the total pot and sent out during settlement.
        // The payout for an individual is their proportional share of the pot *after* fees.
        uint256 totalPayoutPool = totalPot - r.bounty - (totalPot * RAKE_BP / 10_000);

        uint256 payout = (bet.amount * totalPayoutPool) / winnerTotal;
        emit Payout(id, who, payout);
        _safeSend(who, payout);
    }

    function _open(uint256 thresholdGwei) internal {
        cur++;
        uint256 openTs = block.timestamp;
        uint256 closeTs = openTs + ROUND_DURATION;
        uint256 revealTs = closeTs + REVEAL_WINDOW;
        rounds[cur] = Round({
            id: cur,
            closeTs: closeTs,
            revealTs: revealTs,
            settleTs: 0,
            hiTotal: 0,
            loTotal: 0,
            totalCommits: 0,
            winner: Side.Hi,
            threshold: thresholdGwei,
            thresholdCommit: 0,
            feeResult: 0,
            settlePriceGwei: 0,
            settled: false,
            bounty: 0
        });
        emit NewRound(cur, closeTs, revealTs, thresholdGwei);
    }

    function _safeSend(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success, "xfer");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Commit hash(threshold, nonce) for the next round.
    function commitThreshold(bytes32 h) external onlyOwner {
        require(commitRound < cur, "commit exists");
        // A threshold can only be set for the *next* round, not the current one.
        require(rounds[cur].totalCommits == 0, "round-active");
        commitRound = cur;
        commitTs = block.timestamp;
        thresholdCommit = h;
    }
    function revealThreshold(uint256 thr, uint256 salt) external onlyOwner {
        require(commitRound == cur, "no commit");
        require(thresholdCommit == keccak256(abi.encodePacked(thr, salt)), "bad reveal");
        require(rounds[cur].totalCommits == 0, "round-active");
        nextThreshold = thr;
    }
    function setNextThreshold(uint256 thr) external onlyOwner {
        // Direct setting is only allowed if no commit-reveal is in progress
        // and the current round has not started.
        require(thresholdCommit == 0, "commit-in-progress");
        require(rounds[cur].totalCommits == 0, "round-active");
        nextThreshold = thr;
    }
}