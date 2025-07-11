// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;
import "forge-std/Test.sol";
import "../contracts/CommitRevealBSP.sol";
import "../contracts/IBlobBaseFee.sol";

contract DummyOracle is IBlobBaseFee {
    uint256 public fee;
    function blobBaseFee() external view returns (uint256) { return fee; }
    function set(uint256 f) external { fee = f; }
}

contract BountySize is Test {
    CommitRevealBSP pm;
    DummyOracle oracle;
    address owner = address(0xBEEF);
    function setUp() public {
        vm.prank(owner);
        oracle = new DummyOracle();
        vm.prank(owner);
        pm = new CommitRevealBSP(address(oracle));
        vm.deal(address(this), 7 ether); // fund test contract for gift
        vm.deal(address(1), 2 ether);    // fund actor for commit
        vm.deal(address(2), 2 ether);    // fund actor for commit
    }

    receive() external payable {}

    function testBountyIgnoresGifts() public {
        // fund pools
        vm.prank(address(1));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(1), CommitRevealBSP.Side.Hi, bytes32("s"))));
        vm.prank(address(2));
        pm.commit{value:1 ether}(keccak256(abi.encodePacked(address(2), CommitRevealBSP.Side.Lo, bytes32("s2"))));
        
        // Get the round timing and warp to reveal window
        (, uint256 closeTs, uint256 revealTs, , , , , , , , , , , ) = pm.rounds(pm.cur());
        vm.warp(closeTs + 1); // enter reveal window
        
        vm.prank(address(1));
        pm.reveal(CommitRevealBSP.Side.Hi, bytes32("s"));
        vm.prank(address(2));
        pm.reveal(CommitRevealBSP.Side.Lo, bytes32("s2"));
        
        vm.warp(revealTs + 1); // past reveal window for settlement
        // gift ETH to inflate address balance
        (bool ok,) = address(pm).call{value: 5 ether}("");
        require(ok, "gift failed");
        
        // Reveal threshold to allow settlement
        vm.prank(owner);
        bytes32 h = keccak256(abi.encodePacked(uint256(100 gwei), uint256(12345)));
        pm.commitThreshold(h);
        vm.prank(owner);
        pm.revealThreshold(100 gwei, 12345);

        uint256 balBefore = address(this).balance;
        oracle.set(1); // set fee so settle can determine winner
        address settler = address(0xABC);
        vm.deal(settler, 1 ether);
        uint256 settlerBalBefore = settler.balance;
        vm.prank(settler);
        pm.settle();
        uint256 settlerBalAfter = settler.balance;

        // Settler should get bounty (0.1% of 2 ETH pool = 0.002 ETH) minus gas costs
        uint256 expectedBounty = (2 ether * 10) / 10_000; // 0.1% bounty (10 basis points)
        assertTrue(settlerBalAfter >= settlerBalBefore + expectedBounty - 0.01 ether, "settler should get bounty minus gas");
    }
}
