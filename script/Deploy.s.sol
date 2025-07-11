// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Script.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";
import "../contracts/CommitRevealBSP.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        
        // Deploy or use existing Oracle
        address oracle;
        try vm.envAddress("BLOB_ORACLE") returns (address o) {
            oracle = o;
            console.log("Using existing oracle:", oracle);
        } catch {
            // Deploy new oracle with multiple signers if specified
            address[] memory signers = parseSigners();
            uint256 threshold = vm.envOr("ORACLE_THRESHOLD", uint256(1));
            require(threshold <= signers.length, "threshold > signers");
            
            oracle = address(new BlobFeeOracle(signers, threshold));
            console.log("Deployed new oracle:", oracle);
            console.log("Oracle signers:", signers.length);
            console.log("Oracle threshold:", threshold);
        }
        require(oracle != address(0), "oracle required");
        
        // Deploy BlobOptionDesk (BBOD)
        BlobOptionDesk desk = new BlobOptionDesk(oracle);
        console.log("BBOD deployed:", address(desk));
        
        // Deploy CommitRevealBSP (BSP)
        CommitRevealBSP bsp = new CommitRevealBSP(oracle);
        console.log("BSP deployed:", address(bsp));
        
        // Summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Oracle:", oracle);
        console.log("BBOD:", address(desk));
        console.log("BSP:", address(bsp));
        console.log("========================");
        
        vm.stopBroadcast();
    }
    
    function parseSigners() internal view returns (address[] memory) {
        try vm.envString("ORACLE_KEYS") returns (string memory keysStr) {
            // Parse comma-separated private keys
            string[] memory keyStrs = vm.split(keysStr, ",");
            address[] memory signers = new address[](keyStrs.length);
            
            for (uint i = 0; i < keyStrs.length; i++) {
                uint256 key = vm.parseUint(keyStrs[i]);
                signers[i] = vm.addr(key);
            }
            
            return signers;
        } catch {
            // Fallback to single signer (deployer)
            address[] memory signers = new address[](1);
            signers[0] = msg.sender;
            return signers;
        }
    }
}
