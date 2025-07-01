// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "contracts/BlobFeeOracle.sol";
import "contracts/EscrowedSeriesOptionDesk.sol";
import "contracts/CommitRevealBSP.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIV_UINT");
        address deployer = vm.addr(deployerPrivateKey);

        // Give the deployer 5 fake ETH to pay for gas on the fork
        vm.deal(deployer, 5 ether);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy the Oracle with the deployer as the only signer
        address[] memory signers = new address[](1);
        signers[0] = deployer;
        BlobFeeOracle oracle = new BlobFeeOracle(signers, 1);

        // 2. Deploy the main contracts using the new oracle's address
        EscrowedSeriesOptionDesk desk = new EscrowedSeriesOptionDesk(address(oracle));
        CommitRevealBSP pm = new CommitRevealBSP(address(oracle));

        vm.stopBroadcast();

        console.log("---------------------------------");
        console.log("ORACLE DEPLOYED:", address(oracle));
        console.log("BBOD (Desk) DEPLOYED:", address(desk));
        console.log("BSP (Parimutuel) DEPLOYED:", address(pm));
        console.log("---------------------------------");
    }
}
