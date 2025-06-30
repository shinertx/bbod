// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./BaseBlobVault.sol";
import "./IBlobBaseFee.sol";

contract BlobOptionDesk is BaseBlobVault {
    struct Series {
        uint256 strike;
        uint256 expiry;
        uint256 sold;
        uint256 payWei;
        uint256 margin;
    }

    address public immutable writer;
    uint256 public k = 7e15;
    IBlobBaseFee private constant F
        = IBlobBaseFee(0x0000000000000000000000000000000000000000);

    mapping(uint256=>Series) public series;
    mapping(address=>mapping(uint256=>uint256)) public bal;
    uint256 public writerPremiumEscrow;

    constructor() payable { writer = msg.sender; }

    function create(
        uint256 id,
        uint256 strikeGwei,
        uint256 expiry,
        uint256 maxSold
    ) external payable {
        require(msg.sender == writer, "!w");
        require(series[id].strike == 0, "exists");
        uint256 maxPay = (200 - strikeGwei) * 1 gwei * maxSold;
        require(msg.value >= maxPay, "insuff margin");
        series[id] = Series(strikeGwei, expiry, 0, 0, msg.value);
    }

    function premium(uint256 strike, uint256 expiry) public view returns (uint256) {
        uint256 T = expiry - block.timestamp;
        uint256 sigma = 12e9;
        return k * sigma * sqrt(T * 1e18 / 3600) / 1e18;
    }
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) { z = y; uint256 x = y/2+1; while (x < z){ z=x; x=(y/x + x)/2; }} else if (y!=0) z = 1;
    }

    function buy(uint256 id, uint256 qty) external payable {
        Series storage s = series[id];
        require(block.timestamp < s.expiry, "exp");
        uint256 p = premium(s.strike, s.expiry);
        require(msg.value == p * qty, "!prem");
        s.sold += qty;
        bal[msg.sender][id] += qty;
        writerPremiumEscrow += msg.value;
    }

    function settle(uint256 id) external {
        Series storage s = series[id];
        require(block.timestamp >= s.expiry, "!exp");
        require(!settled, "global settled");
        uint256 fee = F.blobBaseFee();
        if (fee > s.strike) {
            s.payWei = (fee - s.strike) * 1 gwei;
        }
        _settle(fee);
    }
    function exercise(uint256 id) external {
        Series storage s = series[id];
        require(settled, "unsettled");
        uint256 qty = bal[msg.sender][id];
        bal[msg.sender][id] = 0;
        uint256 due = qty * s.payWei;
        require(address(this).balance >= due, "insolv");
        payable(msg.sender).transfer(due);
    }

    function withdrawPremiums() external {
        require(msg.sender == writer, "!w");
        uint256 amt = writerPremiumEscrow;
        writerPremiumEscrow = 0;
        payable(writer).transfer(amt);
    }

    function topUpMargin() external payable {}
} 