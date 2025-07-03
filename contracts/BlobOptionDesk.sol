// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract BlobOptionDesk is ReentrancyGuard {
    struct Series {
        uint256 strike;
        uint256 cap;
        uint256 expiry;
        uint256 sold;
        uint256 payWei;
        uint256 margin;
        uint256 maxSold;
    }

    address public immutable writer;
    uint256 public k = 7e15;
    IBlobBaseFee public immutable F;

    mapping(uint256=>Series) public series;
    mapping(uint256=>bool) public seriesSettled;
    mapping(address=>mapping(uint256=>uint256)) public bal;
    // Per-series premium escrow pot and unlock timestamp.
    mapping(uint256 => uint256) public premCollected;
    mapping(uint256 => uint256) public unlockTs;

    // Events
    event PayCapped(uint256 indexed id, uint256 rawWei, uint256 capWei);
    event SettleBounty(uint256 indexed id, address indexed caller, uint256 bountyWei);

    constructor(address feeOracle) payable {
        writer = msg.sender;
        F = IBlobBaseFee(feeOracle);
    }

    function setK(uint256 newK) external {
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
            margin: msg.value,
            maxSold: maxSold
        });
    }

    function premium(uint256 strike, uint256 expiry) public view returns (uint256) {
        uint256 T = expiry - block.timestamp;
        uint256 sigma = 12e9;
        uint256 timePrem = k * sigma * sqrt(T * 1e18 / 3600) / 1e18;
        uint256 intrinsic = F.blobBaseFee() > strike ? (F.blobBaseFee() - strike) * 1 gwei : 0;
        return timePrem > intrinsic ? timePrem : intrinsic;
    }
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y/2+1; while (x < z){ z=x; x=(y/x + x)/2; }} else if (y!=0) z = 1;
    }

    function buy(uint256 id, uint256 qty) external payable {
        Series storage s = series[id];
        require(block.timestamp + 300 < s.expiry, "too-late-to-buy");
        uint256 p = premium(s.strike, s.expiry);
        require(msg.value == p * qty, "!prem");
        require(s.sold + qty <= s.maxSold, "maxSold exceeded");
        s.sold += qty;
        bal[msg.sender][id] += qty;

        // add to series-level premium pot & (re)start 1h escrow timer
        premCollected[id] += msg.value;
        if (unlockTs[id] == 0) {
            unlockTs[id] = block.timestamp + 1 hours;
        }
    }

    function settle(uint256 id) external nonReentrant {
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

        // bounty to caller (post state update to avoid revert grief)
        uint256 bounty = address(this).balance * SETTLE_BOUNTY_BP / 10_000;

        seriesSettled[id] = true;

        if (bounty > 0) {
            payable(msg.sender).transfer(bounty);
            emit SettleBounty(id, msg.sender, bounty);
        }

        if (s.payWei == 0 && msg.sender == writer) {
            uint256 refund = s.margin;
            uint256 bal = address(this).balance;
            if (refund > bal) refund = bal;
            s.margin = 0;
            payable(writer).transfer(refund);
        }
    }
    function exercise(uint256 id) external {
        Series storage s = series[id];
        require(seriesSettled[id], "unsettled");
        uint256 qty = bal[msg.sender][id];
        bal[msg.sender][id] = 0;
        uint256 due = qty * s.payWei;
        require(address(this).balance >= due, "insolv");
        require(s.margin >= due, "margin");
        s.sold -= qty;
        s.margin -= due;
        payable(msg.sender).transfer(due);
    }

    /// @notice Withdraw writer margin once a series is settled.
    ///         If the series expired out-of-the-money the margin can be
    ///         reclaimed immediately.  For in-the-money expiries the writer
    ///         must wait one day to give holders time to exercise.
    function withdrawMargin(uint256 id) external {
        Series storage s = series[id];
        require(msg.sender == writer, "!w");
        require(seriesSettled[id], "unsettled");
        require(
            s.payWei == 0 || block.timestamp > s.expiry + 1 days,
            "grace"
        );
        uint256 amt = s.margin;
        require(amt > 0, "none");
        s.margin = 0;
        payable(writer).transfer(amt);
    }

    uint256 public constant GRACE_PERIOD = 6 hours;

    /// @notice sweep remaining margin after all exercises or timeout
    function sweepMargin(uint256 id) external {
        Series storage s = series[id];
        require(seriesSettled[id], "unsettled");
        require(s.margin > 0, "none");
        require(s.sold == 0 || block.timestamp > s.expiry + GRACE_PERIOD, "pending");
        uint256 amt = s.margin;
        s.margin = 0;
        payable(writer).transfer(amt);
    }

    /// @notice Withdraw unlocked premiums for a single series.
    function withdrawPremium(uint256 id) external {
        require(msg.sender == writer, "!w");
        require(block.timestamp >= unlockTs[id], "escrow");
        uint256 amt = premCollected[id];
        premCollected[id] = 0;
        payable(writer).transfer(amt);
    }

    /// @notice Top up margin for a specific series.  Allows writer (or anyone)
    ///         to add additional collateral if volatility spikes.
    function topUpMargin(uint256 id) external payable {
        Series storage s = series[id];
        require(s.expiry != 0, "bad id");
        s.margin += msg.value;
    }

    uint256 public constant SETTLE_BOUNTY_BP = 10; // 0.10 %
} 