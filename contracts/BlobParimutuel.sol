// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "./BaseBlobVault.sol";
import "./IBlobBaseFee.sol";

contract BlobParimutuel is BaseBlobVault {
    struct Round {
        uint256 closeTs;
        uint256 hiPool;
        uint256 loPool;
        uint256 feeWei;
        uint256 thresholdGwei;
    }
    uint256 public constant RAKE_BP = 500;
    uint256 public cur;
    address public owner;
    IBlobBaseFee private constant F = IBlobBaseFee(0x0000000000000000000000000000000000000000);

    mapping(uint256=>Round) public rounds;
    mapping(uint256=>mapping(address=>uint256)) public hiBet;
    mapping(uint256=>mapping(address=>uint256)) public loBet;

    event Bet(uint256 id,address user,bool hi,uint256 amt);
    event NewRound(uint256 id,uint256 close,uint256 thr);

    modifier onlyOwner(){ require(msg.sender==owner,"!own"); _; }

    constructor() { owner=msg.sender; _open(25); }

    receive() external payable {}

    function betHi() external payable { _bet(true); }
    function betLo() external payable { _bet(false); }

    function _bet(bool hi) internal {
        Round storage r = rounds[cur];
        require(block.timestamp < r.closeTs, "closed");
        if(hi){hiBet[cur][msg.sender]+=msg.value; r.hiPool+=msg.value;}
        else  {loBet[cur][msg.sender]+=msg.value; r.loPool+=msg.value;}
        emit Bet(cur,msg.sender,hi,msg.value);
    }

    function settle() external {
        Round storage r = rounds[cur];
        require(block.timestamp >= r.closeTs + 12, "grief guard");
        uint256 feeGwei = F.blobBaseFee();
        bool hiWin = feeGwei >= r.thresholdGwei;

        uint256 grossPool = r.hiPool + r.loPool;
        uint256 rake = grossPool * RAKE_BP / 10000;
        r.feeWei = rake;
        payable(owner).transfer(rake);

        _settle(feeGwei);
        _open(r.thresholdGwei);
    }

    function claim(uint256 id) external {
        Round storage r = rounds[id];
        require(settled, "unsettled");
        bool hiWin = settlePriceGwei >= r.thresholdGwei;
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

    function _open(uint256 thr) internal {
        cur += 1;
        rounds[cur] = Round({
            closeTs: block.timestamp + 3600,
            hiPool: 0,
            loPool: 0,
            feeWei: 0,
            thresholdGwei: thr
        });
        emit NewRound(cur, block.timestamp+3600, thr);
    }
    function setThreshold(uint256 nextThr) external onlyOwner {
        rounds[cur].thresholdGwei = nextThr;
    }
} 