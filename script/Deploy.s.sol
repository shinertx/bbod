// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Script.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobFeeOracle.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        address oracle;
        try vm.envAddress("BLOB_ORACLE") returns (address o) {
            oracle = o;
        } catch {
            address[] memory signers = new address[](1);
            signers[0] = msg.sender;
            oracle = address(new BlobFeeOracle(signers, 1));
        }
        require(oracle != address(0), "oracle required");
        BlobOptionDesk desk = new BlobOptionDesk(oracle);
        console.log("BBOD:", address(desk));
        vm.stopBroadcast();
    }
}
