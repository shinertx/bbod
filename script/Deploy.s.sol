// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Script.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobParimutuel.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        address oracle = vm.envAddress("BLOB_ORACLE");
        BlobOptionDesk desk = new BlobOptionDesk(oracle);
        BlobParimutuel pm  = new BlobParimutuel(oracle);
        console.log("BBOD:", address(desk));
        console.log("BSP :", address(pm));
        vm.stopBroadcast();
    }
}
