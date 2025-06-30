// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import "forge-std/Script.sol";
import "../contracts/BlobOptionDesk.sol";
import "../contracts/BlobParimutuel.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        BlobOptionDesk desk = new BlobOptionDesk();
        BlobParimutuel pm = new BlobParimutuel();
        console.log("BBOD:", address(desk));
        console.log("BSP :", address(pm));
        vm.stopBroadcast();
    }
} 