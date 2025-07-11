// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract BlobOptionDesk is ReentrancyGuard {
    struct Series {
        uint256 strike;
        uint256 cap;
        uint256 expiry;
        uint256 sold;
        uint256 payWei;
        uint256 margin;
    }

    address public immutable writer;
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
                                   PAUSING
    //////////////////////////////////////////////////////////////////////////*/

    bool public paused;
    modifier notPaused() { require(!paused, "paused"); _; }

    constructor(address feeOracle) payable {
        writer = msg.sender;
        F = IBlobBaseFee(feeOracle);
    }

    function pause(bool p) external {
        require(msg.sender == writer, "!auth");
        paused = p;
    }

    function setK(uint256 newK) external notPaused {
        require(msg.sender == writer, "!auth");
        k = newK;
    }

    function create(
        uint256 id,
        uint256 strikeGwei,
        uint256 capGwei,
        uint256 expiry,
        uint256 maxSold
    ) external payable {
        require(msg.sender == writer, "!w");
        require(series[id].strike == 0, "exists");
        require(expiry > block.timestamp, "bad-expiry");
        require(capGwei > strikeGwei, "cap<=strike");
        require(capGwei - strikeGwei <= 100, "cap too high");
        uint256 maxPay = (capGwei - strikeGwei) * 1 gwei * maxSold;
        require(maxPay <= 100 ether, "liability");
        require(msg.value >= maxPay, "insuff margin");
        series[id] = Series({
            strike: strikeGwei,
            cap: capGwei,
            expiry: expiry,
            sold: 0,
            payWei: 0,
            margin: msg.value
        });
        seriesMaxSold[id] = maxSold;
    }

    function optionCost(uint256 strike, uint256 expiry)
        public view returns (uint256 timeValue, uint256 intrinsic)
    {
        uint256 T = expiry - block.timestamp;
        uint256 sigma = 12e7; // scaled volatility proxy
        timeValue = k * sigma * sqrt((T) * 1e18 / 3600) / 1e18;
        uint256 feeNow = F.blobBaseFee();
        intrinsic = feeNow > strike ? (feeNow - strike) * 1 gwei : 0;
    }

    function premium(uint256 strike, uint256 expiry) public view returns (uint256) {
        (uint256 tv, uint256 iv) = optionCost(strike, expiry);
        return tv + iv;
    }
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y/2+1; while (x < z){ z=x; x=(y/x + x)/2; }} else if (y!=0) z = 1;
    }

    function buy(uint256 id, uint256 qty) external payable notPaused {
        Series storage s = series[id];
        require(block.timestamp + 300 < s.expiry, "too-late-to-buy");
        (uint256 tv, uint256 iv) = optionCost(s.strike, s.expiry);
        uint256 cost = (tv + iv) * qty;
        require(msg.value == cost, "!prem");
        require(s.sold + qty <= seriesMaxSold[id], "maxSold exceeded");
        s.sold += qty;
        bal[msg.sender][id] += qty;

        emit Purchase(id, msg.sender, qty, tv, iv);

        // add to series-level premium pot & (re)start 1h escrow timer
        premCollected[id] += msg.value;
        if (unlockTs[id] == 0) {
            unlockTs[id] = block.timestamp + 1 hours;
        }
    }

    function settle(uint256 id) external nonReentrant notPaused {
        Series storage s = series[id];
        require(block.timestamp >= s.expiry, "!exp");
        require(!seriesSettled[id], "series settled");
        uint256 fee = F.blobBaseFee();
        uint256 cap = s.cap;
        if (fee > cap) fee = cap;
        uint256 rawPay = fee > s.strike ? (fee - s.strike) * 1 gwei : 0;
        uint256 maxPayPerOpt = s.sold == 0 ? 0 : s.margin / s.sold;
        s.payWei = rawPay > maxPayPerOpt ? maxPayPerOpt : rawPay;
        if (rawPay > maxPayPerOpt) {
            emit PayCapped(id, rawPay, maxPayPerOpt);
        }

        // bounty to caller based only on this series' margin
        uint256 bounty = s.margin * SETTLE_BOUNTY_BP / 10_000;

        seriesSettled[id] = true;

        if (bounty > 0) {
            s.margin -= bounty;
            _safeSend(msg.sender, bounty);
            emit SettleBounty(id, msg.sender, bounty);
        }
    }
    function exercise(uint256 id) external nonReentrant notPaused {
        Series storage s = series[id];
        require(seriesSettled[id], "unsettled");
        uint256 qty = bal[msg.sender][id];
        bal[msg.sender][id] = 0;
        uint256 due = qty * s.payWei;
        require(address(this).balance >= due, "insolv");
        require(s.margin >= due, "margin");
        s.sold -= qty;
        s.margin -= due;
        _safeSend(msg.sender, due);
    }

    /// @notice Withdraw writer margin once a series is settled.
    ///         All withdrawals are subject to a `GRACE_PERIOD` after expiry
    ///         to give holders time to exercise their options.
    function withdrawMargin(uint256 id) external nonReentrant notPaused {
        Series storage s = series[id];
        require(msg.sender == writer, "!w");
        require(seriesSettled[id], "unsettled");
        require(block.timestamp > s.expiry + GRACE_PERIOD, "grace");
        uint256 amt = s.margin;
        require(amt > 0, "none");
        s.margin = 0;
        _safeSend(writer, amt);
    }

    /// @notice Grace period after expiry before writer can reclaim margin.
    uint256 public constant GRACE_PERIOD = 1 days;

    /// @notice Withdraw unlocked premiums for a single series.
    function withdrawPremium(uint256 id) external nonReentrant notPaused {
        require(msg.sender == writer, "!auth");
        require(unlockTs[id] != 0 && block.timestamp >= unlockTs[id], "locked");
        uint256 amt = premCollected[id];
        premCollected[id] = 0;
        _safeSend(writer, amt);
    }

    /// @notice Top up margin for a specific series.  Allows writer (or anyone)
    ///         to add additional collateral if volatility spikes.
    function topUpMargin(uint256 id) external payable notPaused {
        Series storage s = series[id];
        require(s.expiry != 0, "bad id");
        s.margin += msg.value;
    }

    uint256 public constant SETTLE_BOUNTY_BP = 10; // 0.10 %

    /*//////////////////////////////////////////////////////////////////////////
                               SAFE ETH TRANSFER
    //////////////////////////////////////////////////////////////////////////*/

    function _safeSend(address to, uint256 amount) internal {
        console.log("Attempting to send", amount, "wei to", to);
        console.log("Contract balance:", address(this).balance);
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "xfer");
    }
}