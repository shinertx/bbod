// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "forge-std/console.sol";

contract BlobOptionDesk is ReentrancyGuard {
    uint256 constant MIN_EXPIRY = 1 hours;
    uint256 constant BUY_CUTOFF = 5 minutes;

    struct Series {
        address writer;
        uint256 strike;
        uint256 cap;
        uint256 expiry;
        uint256 sold;
        uint256 payWei;
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
                                   PAUSING
    //////////////////////////////////////////////////////////////////////////*/

    bool public paused;
    modifier notPaused() { require(!paused, "paused"); _; }

    address public writer;

    constructor(address feeOracle) {
        writer = msg.sender;
        F = IBlobBaseFee(feeOracle);
    }

    function pause(bool p) external {
        require(msg.sender == writer, "not-writer");
        paused = p;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   SERIES MGMT
    //////////////////////////////////////////////////////////////////////////*/

    function create(uint256 id, uint256 strike, uint256 cap, uint256 expiry, uint256 maxSold) public payable {
        if (series[id].writer != address(0)) revert("series-exists");
        if (strike == 0) revert("0-strike");
        if (expiry < block.timestamp + MIN_EXPIRY) revert("too-soon");
        if (msg.value == 0) revert("no-margin");

        series[id] = Series({
            writer: msg.sender,
            strike: strike,
            cap: cap,
            expiry: expiry,
            sold: 0,
            payWei: 0,
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
        if (block.timestamp < s.expiry) revert("too-soon");
        if (bal[msg.sender][id] < num) revert("insufficient-balance");

        bal[msg.sender][id] -= num;
        uint256 baseFee = F.blobBaseFee();
        uint256 payout;
        if (baseFee > s.strike) {
            payout = baseFee - s.strike;
            if (payout > s.cap) {
                payout = s.cap;
                emit PayCapped(id, baseFee - s.strike, s.cap);
            }
        }
        s.payWei += num * payout;
        payable(msg.sender).transfer(num * payout);
    }

    function settle(uint256 id) public {
        Series storage s = series[id];
        if (s.writer == address(0)) revert("bad-series");
        if (seriesSettled[id]) revert("already-settled");
        if (block.timestamp < s.expiry + 1 hours) revert("too-soon");
        seriesSettled[id] = true;

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
        if (s.margin == 0) revert("no-margin");

        uint256 margin = s.margin;
        s.margin = 0;
        payable(msg.sender).transfer(margin - s.payWei - (margin / 100));
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
        uint256 t = expiry - block.timestamp;
        return k * t + intrinsic(strike);
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
        console.log("Attempting to send", amount, "wei to", to);
        console.log("Contract balance:", address(this).balance);
        (bool ok, ) = payable(to).call{value: amount}("");
        require(ok, "xfer");
    }
    receive() external payable {}
}