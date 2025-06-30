// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IBlobBaseFee.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title EscrowedSeriesOptionDesk
 * @notice Minimal, fully-escrowed European call option vault.  Each option
 *         series has its own isolated margin bucket so that ITM settlement of
 *         one series cannot drain collateral earmarked for another.
 *
 *         Writer supplies the maximum possible payout for the series at create()
 *         time; buyers then pay a flat premium (placeholder) to purchase
 *         options.  Anyone can call settle() once the oracle fee for the epoch
 *         is final, and holders can exercise afterwards.  After a short grace
 *         period the writer may sweep any remaining escrow.
 */
contract EscrowedSeriesOptionDesk is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////////////////
                                    DATA TYPES
    //////////////////////////////////////////////////////////////////////////*/

    struct Series {
        uint256 strikeGwei; // strike price (gwei)
        uint256 capGwei;    // collateralisation cap per option (gwei)
        uint256 expiry;     // unix ts
        uint256 payWei;     // payoff per option if ITM
        uint256 sold;       // qty sold
        uint256 escBalance; // ETH escrowed solely for this series
        bool    settled;    // settlement flag
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event Created(uint256 indexed id, uint256 strikeGwei, uint256 expiry, uint256 maxPayoutWei);
    event Settled(uint256 indexed id, uint256 feeGwei, uint256 payWei);
    event Exercised(uint256 indexed id, address indexed holder, uint256 qty, uint256 paid);
    event Swept(uint256 indexed id, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                     STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    mapping(uint256 => Series) public sData;                      // id => series data
    mapping(uint256 => mapping(address => uint256)) public bal;   // id => holder => qty

    address public immutable writer;          // option writer / vault owner
    IBlobBaseFee public immutable F;          // blob base-fee oracle

    /*//////////////////////////////////////////////////////////////////////////
                                   CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(address oracle) {
        writer = msg.sender;
        F = IBlobBaseFee(oracle);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                WRITER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Create a new option series with its own isolated margin bucket.
    /// @param id       Series identifier (must be unused).
    /// @param strike   Strike price in gwei.
    /// @param cap      Collateralisation cap per option in gwei.
    /// @param expiry   Expiry timestamp (unix seconds).
    /// @param maxSold  Maximum number of options that can be sold.
    function create(
        uint256 id,
        uint256 strike,
        uint256 cap,
        uint256 expiry,
        uint256 maxSold
    ) external payable {
        require(msg.sender == writer, "!w");
        require(sData[id].expiry == 0, "exists");
        require(cap > strike, "cap<=strike");
        require(cap - strike <= 100, "cap too high");
        uint256 maxPay = (cap - strike) * 1 gwei * maxSold;
        require(maxPay <= 100 ether, "liability");
        require(msg.value >= maxPay, "escrow");

        sData[id] = Series({
            strikeGwei: strike,
            capGwei: cap,
            expiry: expiry,
            payWei: 0,
            sold: 0,
            escBalance: msg.value,
            settled: false
        });

        emit Created(id, strike, expiry, maxPay);
    }

    /*//////////////////////////////////////////////////////////////////////////
                               BUYER-FACING METHODS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Real premium curve – proportional to implied vol * sqrt(T)
    ///         This is a toy formula; tweak sigma/base via calibration.
    function premium(uint256 id) public view returns (uint256) {
        Series storage S = sData[id];
        require(S.expiry != 0, "bad id");

        uint256 T = S.expiry > block.timestamp ? S.expiry - block.timestamp : 0;
        if (T > 30 days) T = 30 days;
        if (T == 0) return 0;

        uint256 sigma = 25e8; // 2.5e9 = 250% annualised vol in gwei units
        uint256 base = 1e12;  // scaling constant (wei)

        uint256 premiumWei = base * sigma * _sqrt((T * 1e18) / 31_536_000) / 1e18;
        return premiumWei;
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Purchase `qty` options in series `id`.
    function buy(uint256 id, uint256 qty) external payable {
        Series storage S = sData[id];
        require(S.expiry != 0, "bad id");
        require(block.timestamp < S.expiry, "exp");
        require(msg.value == premium(id) * qty, "prem");

        bal[id][msg.sender] += qty;
        S.sold += qty;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                 SETTLEMENT FLOW
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Anyone can settle once the series has expired.  Locks in the
    ///         oracle base-fee at first call.
    function settle(uint256 id) external {
        Series storage S = sData[id];
        require(S.expiry != 0, "bad id");
        require(block.timestamp >= S.expiry, "early");
        require(!S.settled, "done");

        uint256 fee = F.blobBaseFee();
        uint256 cap = S.capGwei;
        if (fee > cap) fee = cap; // clamp to collateral cap

        if (fee > S.strikeGwei) {
            S.payWei = (fee - S.strikeGwei) * 1 gwei;
        }
        S.settled = true;
        emit Settled(id, fee, S.payWei);
    }

    /// @notice Exercise in-the-money options for series `id`.
    function exercise(uint256 id) external nonReentrant {
        Series storage S = sData[id];
        require(S.settled, "unsettled");

        uint256 qty = bal[id][msg.sender];
        bal[id][msg.sender] = 0;
        uint256 due = qty * S.payWei;
        require(due > 0, "!itm");
        require(S.escBalance >= due, "esc");

        S.escBalance -= due;
        payable(msg.sender).transfer(due);
        emit Exercised(id, msg.sender, qty, due);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MARGIN MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Writer withdraws leftover escrow after a 1-hour grace period.
    function sweepMargin(uint256 id) external nonReentrant {
        Series storage S = sData[id];
        require(msg.sender == writer, "!w");
        require(S.settled && block.timestamp > S.expiry + 1 hours, "wait");

        uint256 amt = S.escBalance;
        S.escBalance = 0;
        payable(writer).transfer(amt);
        emit Swept(id, amt);
    }
} 