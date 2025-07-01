// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./BaseBlobVault.sol";
import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract BlobParimutuel is BaseBlobVault, ReentrancyGuard {
    struct Round {
        uint256 closeTs;
        uint256 hiPool;
        uint256 loPool;
        uint256 feeWei;
        uint256 thresholdGwei;
        uint256 settlePriceGwei;
    }
    uint256 public constant RAKE_BP = 500;
    uint256 public constant BET_CUTOFF = 300; // seconds before closeTs when betting stops
    uint256 public constant SETTLE_BOUNTY_BP = 10; // 0.10 %
    uint256 public cur;
    address public owner;
    uint256 public nextThresholdGwei; // threshold to apply to the *next* round if preset
    IBlobBaseFee public immutable F;

    mapping(uint256=>Round) public rounds;
    mapping(uint256=>mapping(address=>uint256)) public hiBet;
    mapping(uint256=>mapping(address=>uint256)) public loBet;

    event Bet(uint256 id,address user,bool hi,uint256 amt);
    event NewRound(uint256 id,uint256 close,uint256 thr);
    event RefundAll(uint256 indexed id);
    event RoundVoided(uint256 indexed id, uint256 refundWei);
    event SettleBounty(uint256 indexed id, address indexed caller, uint256 bountyWei);

    modifier onlyOwner(){ require(msg.sender==owner,"!own"); _; }

    constructor(address feeOracle) {
        owner = msg.sender;
        F = IBlobBaseFee(feeOracle);
        _open(25);
    }

    receive() external payable {}

    function betHi() external payable { _bet(true); }
    function betLo() external payable { _bet(false); }

    function _bet(bool hi) internal {
        Round storage r = rounds[cur];
        require(block.timestamp < r.closeTs - BET_CUTOFF, "cutoff");
        if(hi){hiBet[cur][msg.sender]+=msg.value; r.hiPool+=msg.value;}
        else  {loBet[cur][msg.sender]+=msg.value; r.loPool+=msg.value;}
        emit Bet(cur,msg.sender,hi,msg.value);
    }

    function settle() external nonReentrant {
        Round storage r = rounds[cur];
        require(block.timestamp >= r.closeTs + 12, "grief guard");
        uint256 feeGwei = F.blobBaseFee();
        // store settle price early
        r.settlePriceGwei = feeGwei;

        uint256 grossPool = r.hiPool + r.loPool;

        // winner-less rescue
        if (r.hiPool == 0 || r.loPool == 0) {
            r.feeWei = 0; // no rake
            emit RefundAll(cur);
            emit RoundVoided(cur, r.hiPool + r.loPool);
            _settle(feeGwei);
            _open(r.thresholdGwei);
            return;
        }

        // permissionless settlement bounty (0.1% of contract balance) – execute only for contested rounds
        uint256 bounty = address(this).balance * SETTLE_BOUNTY_BP / 10_000;
        if (bounty > 0) {
            payable(msg.sender).transfer(bounty);
            // deduct from rake later by reducing grossPool pre-rake
            grossPool -= bounty;
            emit SettleBounty(cur, msg.sender, bounty);
        }

        uint256 rake = grossPool * RAKE_BP / 10000;
        r.feeWei = rake;
        // transfer rake after state write
        payable(owner).transfer(rake);

        _settle(feeGwei);
        _open(r.thresholdGwei);
    }

    function claim(uint256 id) external nonReentrant {
        Round storage r = rounds[id];
        require(r.settlePriceGwei != 0, "round unsettled");
        // If winner-less round, everyone can refund 99.5 %
        if (r.hiPool == 0 || r.loPool == 0) {
            uint256 stake = hiBet[id][msg.sender] + loBet[id][msg.sender];
            require(stake > 0, "none");
            hiBet[id][msg.sender] = 0; loBet[id][msg.sender]=0;
            uint256 bal = address(this).balance;
            uint256 refund = stake > bal ? bal : stake;
            payable(msg.sender).transfer(refund);
            return;
        }

        bool hiWin = r.settlePriceGwei >= r.thresholdGwei;
        uint256 share = hiWin ? hiBet[id][msg.sender] : loBet[id][msg.sender];
        require(share>0, "none");
        if(hiWin) hiBet[id][msg.sender]=0; else loBet[id][msg.sender]=0;
        uint256 winPool = hiWin ? r.hiPool : r.loPool;
        uint256 totalPool = r.hiPool + r.loPool - r.feeWei;
        uint256 pay = share * totalPool / winPool;
        // In rare cases of truncation, pay might exceed balance by 1 wei; cap it.
        uint256 bal = address(this).balance;
        if (pay > bal) pay = bal;
        payable(msg.sender).transfer(pay);
    }

    function _open(uint256 thrFallback) internal {
        settled = false;
        cur += 1;
        uint256 thr = nextThresholdGwei != 0 ? nextThresholdGwei : thrFallback;
        // clear for subsequent rounds
        nextThresholdGwei = 0;
        rounds[cur] = Round({
            closeTs: block.timestamp + 3600,
            hiPool: 0,
            loPool: 0,
            feeWei: 0,
            thresholdGwei: thr,
            settlePriceGwei: 0
        });
        emit NewRound(cur, block.timestamp+3600, thr);
    }

    /// @notice Set threshold for the *next* round; cannot modify current round once bets exist.
    function setNextThreshold(uint256 thr) external onlyOwner {
        Round storage r = rounds[cur];
        require(r.hiPool == 0 && r.loPool == 0, "bets placed");
        nextThresholdGwei = thr;
    }

    /// @notice Collect stray wei that might accumulate due to rounding or refunds.
    function sweepDust() external onlyOwner {
        // allow only after current round is finished and a month has passed
        require(block.timestamp > rounds[cur].closeTs + 30 days, "too-soon");
        uint256 tracked = rounds[cur].hiPool + rounds[cur].loPool;
        uint256 excess = address(this).balance > tracked ? address(this).balance - tracked : 0;
        if (excess > 0) payable(owner).transfer(excess);
    }
} 