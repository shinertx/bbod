// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract BlobOptionDesk is ReentrancyGuard {
    uint256 constant MIN_EXPIRY = 1 hours;
    uint256 public constant BUY_CUTOFF = 5 minutes;

    struct Series {
        address writer;
        uint256 strike;
        uint256 cap;
        uint256 expiry;
        uint256 sold;
        uint256 payoutPerUnit;
        uint256 margin;
        bool paidOut;
    }

    /// @notice Premium scale factor. Tuned so one-hour options cost ~0.001 ETH.
    uint256 public k = 7e13;
    IBlobBaseFee public immutable F;

    mapping(uint256=>Series) public series;
    mapping(uint256=>bool) public seriesSettled;
    mapping(uint256=>uint256) public seriesMaxSold;
    mapping(address=>mapping(uint256=>uint256)) public bal;
    // Per-series premium escrow pot and unlock timestamp.
    mapping(uint256 => uint256) public premCollected;
    mapping(uint256 => uint256) public unlockTs;

    // Events
    event PayCapped(uint256 indexed id, uint256 rawWei, uint256 capWei);
    event SettleBounty(uint256 indexed id, address indexed caller, uint256 bountyWei);
    event Purchase(uint256 indexed id, address indexed buyer, uint256 qty, uint256 timeValue, uint256 intrinsic);

    /*//////////////////////////////////////////////////////////////////////////
                                   ACCESS CONTROL
    //////////////////////////////////////////////////////////////////////////*/

    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "zero-address");
        owner = newOwner;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   PAUSING
    //////////////////////////////////////////////////////////////////////////*/

    bool public paused;
    modifier notPaused() { require(!paused, "paused"); _; }

    constructor(address feeOracle) {
        owner = msg.sender;
        F = IBlobBaseFee(feeOracle);
    }

    function pause(bool p) external onlyOwner {
        paused = p;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   SERIES MGMT
    //////////////////////////////////////////////////////////////////////////*/

    function create(uint256 id, uint256 strike, uint256 cap, uint256 expiry, uint256 maxSold) public payable {
        if (series[id].writer != address(0)) revert("series-exists");
        if (strike == 0) revert("0-strike");
        if (cap <= strike) revert("cap-le-strike");
        if (expiry < block.timestamp + MIN_EXPIRY) revert("too-soon");
        if (msg.value == 0) revert("no-margin");

        uint256 maxPayout = (cap - strike) * 1 gwei;
        uint256 requiredMargin = maxSold * maxPayout;
        require(msg.value >= requiredMargin, "insufficient-margin");

        series[id] = Series({
            writer: msg.sender,
            strike: strike,
            cap: cap,
            expiry: expiry,
            sold: 0,
            payoutPerUnit: 0,
            margin: msg.value,
            paidOut: false
        });
        seriesMaxSold[id] = maxSold;
        unlockTs[id] = expiry + 1 hours;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   TRADING
    //////////////////////////////////////////////////////////////////////////*/

    function buy(uint256 id, uint256 num) public payable notPaused {
        Series storage s = series[id];
        if (s.writer == address(0)) revert("bad-series");
        if (block.timestamp > s.expiry - BUY_CUTOFF) revert("too-late-to-buy");
        if (s.sold + num > seriesMaxSold[id]) revert("sold-out");
        uint256 expected = premium(s.strike, s.expiry) * num;
        if (msg.value != expected) revert("bad-premium");
        s.sold += num;
        bal[msg.sender][id] += num;
        premCollected[id] += msg.value;
        emit Purchase(id, msg.sender, num, premium(s.strike, s.expiry) - intrinsic(s.strike), intrinsic(s.strike));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    function exercise(uint256 id, uint256 num) public nonReentrant {
        Series storage s = series[id];
        if (s.writer == address(0)) revert("bad-series");
        if (!seriesSettled[id]) revert("not-settled");
        if (block.timestamp > s.expiry + GRACE_PERIOD()) revert("too-late-to-exercise");
        if (bal[msg.sender][id] < num) revert("insufficient-balance");

        bal[msg.sender][id] -= num;
        uint256 totalPayout = num * s.payoutPerUnit;
        payable(msg.sender).transfer(totalPayout);
    }

    function settle(uint256 id) public {
        Series storage s = series[id];
        if (s.writer == address(0)) revert("bad-series");
        if (seriesSettled[id]) revert("already-settled");
        if (block.timestamp < s.expiry) revert("too-soon");
        seriesSettled[id] = true;

        uint256 baseFee = F.blobBaseFee();
        uint256 payout;
        if (baseFee > s.strike) {
            payout = (baseFee - s.strike) * 1 gwei;
            if (baseFee > s.cap) {
                payout = (s.cap - s.strike) * 1 gwei;
                emit PayCapped(id, baseFee - s.strike, s.cap);
            }
        }
        s.payoutPerUnit = payout;

        uint256 bounty = s.margin / 100;
        payable(msg.sender).transfer(bounty);
        emit SettleBounty(id, msg.sender, bounty);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   WITHDRAWALS
    //////////////////////////////////////////////////////////////////////////*/

    function withdrawMargin(uint256 id) public {
        Series storage s = series[id];
        if (s.writer != msg.sender) revert("not-writer");
        if (!seriesSettled[id]) revert("not-settled");
        if (block.timestamp < s.expiry + GRACE_PERIOD()) revert("grace");
        if (s.margin == 0) revert("no-margin");

        uint256 totalPayoutLiability = s.sold * s.payoutPerUnit;
        uint256 margin = s.margin;
        uint256 bounty = margin / 100;
        
        // CRITICAL: Prevent underflow that would drain contract
        require(margin >= totalPayoutLiability + bounty, "insufficient-margin");
        
        s.margin = 0;
        uint256 remainingMargin = margin - totalPayoutLiability - bounty;
        
        if (remainingMargin > 0) {
            payable(msg.sender).transfer(remainingMargin);
        }
    }

    function withdrawPremium(uint256 id) public {
        Series storage s = series[id];
        if (s.writer != msg.sender) revert("not-writer");
        if (block.timestamp < unlockTs[id]) revert("locked");
        if (s.paidOut) revert("paid-out");

        s.paidOut = true;
        uint256 amount = premCollected[id];
        premCollected[id] = 0;
        payable(msg.sender).transfer(amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   VIEW
    //////////////////////////////////////////////////////////////////////////*/
    function GRACE_PERIOD() public pure returns (uint256) {
        return 1 hours;
    }

    function SETTLE_BOUNTY_BP() public pure returns (uint256) {
        return 100;
    }

    function premium(uint256 strike, uint256 expiry) public view returns (uint256) {
        uint256 timeToExpiry = expiry - block.timestamp;
        if (timeToExpiry == 0) return intrinsic(strike);
        
        // Dynamic volatility-aware pricing
        uint256 currentFee = F.blobBaseFee();
        uint256 volMultiplier = 1e18;
        
        // Increase vol during congestion (fee > 20 gwei = high congestion)
        if (currentFee > 20 * 1 gwei) {
            volMultiplier = 2e18; // 2x volatility premium
        }
        if (currentFee > 50 * 1 gwei) {
            volMultiplier = 4e18; // 4x volatility premium during extreme congestion
        }
        
        uint256 timeValue = (k * sqrt(timeToExpiry) * volMultiplier) / 1e18;
        return timeValue + intrinsic(strike);
    }

    function intrinsic(uint256 strike) public view returns (uint256) {
        uint256 feeNow = F.blobBaseFee();
        return feeNow > strike ? (feeNow - strike) * 1 gwei : 0;
    }
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y/2+1; while (x < z){ z=x; x=(y/x + x)/2; }} else if (y!=0) z = 1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                               SAFE ETH TRANSFER
    //////////////////////////////////////////////////////////////////////////*/

    function _safeSend(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "xfer");
    }
    receive() external payable {}
}