// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IBlobBaseFee} from "./IBlobBaseFee.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract BlobOptionDesk is ReentrancyGuard, Pausable, Ownable {
    uint256 constant MIN_EXPIRY = 1 hours;
    uint256 public constant BUY_CUTOFF = 5 minutes;
    uint256 public constant MAX_ORACLE_DELAY = 1 hours;
    uint256 public constant GRACE_PERIOD = 1 hours;
    uint256 public constant MIN_MARGIN_REQUIREMENT = 0.01 ether;

    struct Series {
        address writer;
        uint256 strike; // in gwei
        uint256 cap;    // in gwei
        uint256 expiry;
        uint256 sold;
        uint256 payoutPerUnit; // in wei
        uint256 margin;
        bool paidOut;
        uint256 maxSold;
    }

    /// @notice Premium scale factor.
    uint256 public k = 7e13;
    IBlobBaseFee public immutable F;

    mapping(uint256 => Series) public series;
    uint256 public nextSeriesId;

    // Per-series premium escrow pot and unlock timestamp.
    mapping(uint256 => uint256) public premCollected;
    mapping(uint256 => uint256) public unlockTs;
    mapping(address => mapping(uint256 => uint256)) public balances;

    // Custom Errors
    error SeriesExists();
    error ZeroStrike();
    error CapLessThanStrike();
    error ExpiryTooSoon();
    error NoMarginProvided();
    error ZeroMaxSold();
    error InsufficientMargin();
    error BadSeries();
    error TooLateToBuy();
    error ZeroQuantity();
    error SoldOut();
    error IncorrectPremium();
    error NotSettled();
    error TooLateToExercise();
    error InsufficientBalance();
    error AlreadySettled();
    error SettleTooSoon();
    error NotWriter();
    error GracePeriodActive();
    error MarginAlreadyWithdrawn();
    error PremiumLocked();
    error PremiumAlreadyWithdrawn();
    error StaleOraclePrice();

    // Events
    event SeriesCreated(uint256 indexed id, address indexed writer, uint256 strike, uint256 cap, uint256 expiry, uint256 maxSold);
    event PayCapped(uint256 indexed id, uint256 rawWei, uint256 capWei);
    event SettleBounty(uint256 indexed id, address indexed caller, uint256 bountyWei);
    event Purchase(uint256 indexed id, address indexed buyer, uint256 qty, uint256 premium);
    event Exercised(uint256 indexed id, address indexed user, uint256 qty, uint256 payout);
    event MarginWithdrawn(uint256 indexed id, address indexed writer, uint256 amount);
    event PremiumWithdrawn(uint256 indexed id, address indexed writer, uint256 amount);


    constructor(address feeOracle, address initialOwner) Ownable(initialOwner) {
        F = IBlobBaseFee(feeOracle);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   SERIES MGMT
    //////////////////////////////////////////////////////////////////////////*/

    function create(uint256 strike, uint256 cap, uint256 expiry, uint256 maxSold) external payable whenNotPaused {
        if (strike == 0) revert ZeroStrike();
        if (cap <= strike) revert CapLessThanStrike();
        if (expiry < block.timestamp + MIN_EXPIRY) revert ExpiryTooSoon();
        if (msg.value < MIN_MARGIN_REQUIREMENT) revert NoMarginProvided();
        if (maxSold == 0) revert ZeroMaxSold();

        // [CRITICAL-01] Enforce sufficient margin for max possible payout
        uint256 requiredMargin = maxSold * (cap - strike) * 1 gwei;
        if (msg.value < requiredMargin) revert InsufficientMargin();

        uint256 id = nextSeriesId++;
        
        series[id] = Series({
            writer: msg.sender,
            strike: strike,
            cap: cap,
            expiry: expiry,
            sold: 0,
            payoutPerUnit: 0,
            margin: msg.value,
            paidOut: false,
            maxSold: maxSold
        });
        unlockTs[id] = expiry + GRACE_PERIOD;
        emit SeriesCreated(id, msg.sender, strike, cap, expiry, maxSold);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   TRADING
    //////////////////////////////////////////////////////////////////////////*/

    function buy(uint256 id, uint256 num, uint256 maxPremium) external payable whenNotPaused {
        Series storage s = series[id];
        if (s.writer == address(0)) revert BadSeries();
        if (block.timestamp > s.expiry - BUY_CUTOFF) revert TooLateToBuy();
        if (num == 0) revert ZeroQuantity();
        if (s.sold + num > s.maxSold) revert SoldOut();
        
        uint256 expected = premium(s.strike, s.expiry) * num;
        // [MEDIUM-03] Slippage protection
        if (expected > maxPremium) revert IncorrectPremium();
        if (msg.value != expected) revert IncorrectPremium();

        s.sold += num;
        balances[msg.sender][id] += num;
        premCollected[id] += msg.value;
        emit Purchase(id, msg.sender, num, msg.value);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   SETTLEMENT
    //////////////////////////////////////////////////////////////////////////*/

    function exercise(uint256 id, uint256 num) external nonReentrant {
        Series storage s = series[id];
        if (s.writer == address(0)) revert BadSeries();
        if (s.payoutPerUnit == 0) revert NotSettled(); // Simplified check
        if (block.timestamp > s.expiry + GRACE_PERIOD) revert TooLateToExercise();
        if (balances[msg.sender][id] < num) revert InsufficientBalance();

        balances[msg.sender][id] -= num;
        uint256 totalPayout = num * s.payoutPerUnit;
        
        (bool success, ) = msg.sender.call{value: totalPayout}("");
        require(success, "Transfer failed");
        emit Exercised(id, msg.sender, num, totalPayout);
    }

    function settle(uint256 id) external nonReentrant {
        Series storage s = series[id];
        if (s.writer == address(0)) revert BadSeries();
        if (s.payoutPerUnit > 0 && s.margin == 0) revert AlreadySettled(); // Simplified check
        if (block.timestamp < s.expiry) revert SettleTooSoon();

        // [MEDIUM-01] Stale oracle price check
        (uint256 baseFee, uint256 feeTimestamp) = F.latest();
        if (block.timestamp - feeTimestamp > MAX_ORACLE_DELAY) revert StaleOraclePrice();

        uint256 payout;
        if (baseFee > s.strike) {
            payout = (baseFee - s.strike) * 1 gwei;
            if (baseFee > s.cap) {
                payout = (s.cap - s.strike) * 1 gwei;
                emit PayCapped(id, (baseFee - s.strike) * 1 gwei, payout);
            }
        }
        s.payoutPerUnit = payout;

        uint256 bounty = s.margin / 100; // 1% bounty
        (bool success, ) = msg.sender.call{value: bounty}("");
        require(success, "Bounty transfer failed");
        emit SettleBounty(id, msg.sender, bounty);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   WITHDRAWALS
    //////////////////////////////////////////////////////////////////////////*/

    function withdrawMargin(uint256 id) external nonReentrant {
        Series storage s = series[id];
        if (s.writer != msg.sender) revert NotWriter();
        if (s.payoutPerUnit == 0) revert NotSettled();
        if (block.timestamp < s.expiry + GRACE_PERIOD) revert GracePeriodActive();
        if (s.margin == 0) revert MarginAlreadyWithdrawn();

        uint256 totalPayoutLiability = s.sold * s.payoutPerUnit;
        uint256 margin = s.margin;
        uint256 bounty = margin / 100;
        
        uint256 requiredToHold = totalPayoutLiability + bounty;
        if (margin < requiredToHold) { // Should not happen with correct creation logic
             // This case indicates a catastrophic failure, lock funds
        } else {
            uint256 remainingMargin = margin - requiredToHold;
            s.margin = 0;
            if (remainingMargin > 0) {
                (bool success, ) = msg.sender.call{value: remainingMargin}("");
                require(success, "Transfer failed");
            }
            emit MarginWithdrawn(id, msg.sender, remainingMargin);
        }
    }

    function withdrawPremium(uint256 id) external nonReentrant {
        Series storage s = series[id];
        if (s.writer != msg.sender) revert NotWriter();
        if (block.timestamp < unlockTs[id]) revert PremiumLocked();
        if (s.paidOut) revert PremiumAlreadyWithdrawn();

        s.paidOut = true;
        uint256 amount = premCollected[id];
        if (amount > 0) {
            premCollected[id] = 0;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "Transfer failed");
        }
        emit PremiumWithdrawn(id, msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   VIEW
    //////////////////////////////////////////////////////////////////////////*/

    function premium(uint256 strike, uint256 expiry) public view returns (uint256) {
        if (block.timestamp >= expiry) return intrinsic(strike);
        uint256 timeToExpiry = expiry - block.timestamp;
        
        uint256 timeValue = (k * sqrt(timeToExpiry)); // Simplified for gas
        return (timeValue / 1e9) + intrinsic(strike); // Return in gwei
    }

    function intrinsic(uint256 strike) public view returns (uint256) {
        (uint256 feeNow, ) = F.latest();
        return feeNow > strike ? (feeNow - strike) : 0; // Return in gwei
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y + x * x) / (2 * x);
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}