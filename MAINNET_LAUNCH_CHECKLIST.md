# Mainnet Launch Checklist

**IMPORTANT: LAUNCHING WITHOUT A PROFESSIONAL AUDIT IS EXTREMELY RISKY. By following this guide, you acknowledge that you are deploying a protocol that has not been vetted by an external security firm, which could result in the total and permanent loss of all funds.**

---

## 1. Pre-Flight: Final Configuration & Security

-   [ ] **Secure Your Private Key:** Ensure the `PRIVATE_KEY` in your `.env` file is for a new, secure wallet that will be the `owner` of the contracts. This wallet should have sufficient ETH for deployment gas fees. **NEVER commit your `.env` file to a public repository.**
-   [ ] **Set RPC Endpoint:** Verify that the `RPC_URL` in your `.env` file points to a reliable mainnet RPC provider (e.g., Infura, Alchemy).
-   [ ] **Review Contract Parameters:** Double-check the constants in `CommitRevealBSP.sol` and `BlobOptionDesk.sol` (e.g., `RAKE_BP`, `MIN_BET`, `MAX_BET_PER_ADDRESS`). These will be immutable after deployment.
-   [ ] **Gas Price Check:** Check current mainnet gas prices to ensure you have enough ETH and to avoid a stuck deployment transaction.

## 2. Deployment: Pushing Contracts to Mainnet

-   [ ] **Run the Deployment Script:** Execute the following command from your terminal. This will use the `Deploy.s.sol` script to deploy all necessary contracts.

    ```bash
    forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify -vvvv
    ```

-   [ ] **Save Contract Addresses:** The script will output the addresses of the deployed `CommitRevealBSP` and `BlobOptionDesk` contracts. **Save these addresses immediately.** They are critical for verification and for configuring your keeper bots.
-   [ ] **Verify on Etherscan:** The `--verify` flag in the command attempts to automatically verify the contract source code on Etherscan. Confirm that this was successful by visiting the contract addresses on `etherscan.io`. If it failed, you may need to do it manually.

## 3. Post-Launch: Activate the System

-   [ ] **Fund the Oracle:** The `BlobFeeOracle` requires ETH to pay for its own transaction fees when pushing data. Send a small amount of ETH (e.g., 0.1 ETH) to the deployed `BlobFeeOracle` contract address.
-   [ ] **Configure Keeper Bots:** Update the `config/agents.json` file with the newly deployed contract addresses.
-   [ ] **Start the Keeper Bots:** Launch the necessary keeper bots to operate the protocol. The most critical are the `settleBot` and the `oracleBot`.

    ```bash
    node dist/daemon/oracleBot.js
    node dist/daemon/settleBot.js
    # ... and any other bots you intend to run (ivBot, etc.)
    ```

## 4. Go-Live: Announce & Monitor

-   [ ] **Update Frontend:** Update your frontend application with the new mainnet contract addresses and ABI.
-   [ ] **Announce:** Share the news and the frontend URL with your community.
-   [ ] **MONITOR CLOSELY:** Watch the contract interactions on Etherscan and monitor the logs from your keeper bots vigilantly, especially in the first 24-48 hours. Be prepared to pause the contracts using the `pause()` function if you notice any unusual activity.

---

**Again, proceeding without an audit carries a high risk of catastrophic failure. Please be careful.**
