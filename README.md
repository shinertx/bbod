# Blob Edge Stack


A decentralized derivatives suite for hedging and speculating on Ethereum's EIP-4844 blob gas fees.

This repository implements two core primitives: a fixed-strike options desk (**BBOD**) and a parimutuel betting pool (**BSP**), both powered by a shared, decentralized oracle for the `BLOBBASEFEE`.

-----

## Overview

  * **`contracts/`**: Audited, production-ready smart contracts for the oracle, options desk, and parimutuel system.
  * **`daemon/`**: Off-chain services for fetching blob fees and relaying data to the frontend.
  * **`bots/`**: The operational "brain" of the protocol for automated settlement, market-making, and risk management.
  * **`test/`**: A comprehensive Foundry test suite, including unit and fuzz tests.
  * **`script/`**: Deployment and operational scripts.
  * **`frontend/`**: A minimal Next.js UI for monitoring the live system.

-----

## Core Concepts

This protocol allows users to take two primary positions on the future price of blob space:

1.  **Hedging with `EscrowedSeriesOptionDesk` (BBOD)**

      * **What it is:** An insurance market. Users (like L2 rollups) can pay a small upfront fee (a *premium*) to buy a call option. This option pays out if the blob fee spikes above a certain *strike price*, effectively capping their maximum data posting costs.
      * **Purpose:** To manage risk.

2.  **Speculating with `CommitRevealBSP` (BSP)**

      * **What it is:** A fast-paced betting arena. Users place bets on whether the blob fee will be "High" or "Low" relative to a set threshold within an hourly window.
      * **Purpose:** To profit from short-term volatility.

-----

## Quick Start

This guide gets an experienced developer from a fresh clone to a running test environment on a mainnet fork in under 10 minutes.

```bash
# 1. Clone & Initialize
git clone https://github.com/shinertx/bbod.git
cd bbod
git submodule update --init
cp .env.example .env
# --> Fill in your RPC and a burner PRIV in .env

# 2. Install Dependencies
npm install -g pnpm
pnpm install
pnpm --prefix frontend install

# 3. Test & Deploy to Fork
forge test -vv --root .
source .env && forge script script/Deploy.s.sol --fork-url $RPC --broadcast --root .
# --> Copy the deployed BBOD, BSP, and ORACLE addresses and add them to your .env file

# 4. Run the Full Stack
npm run ws &    # Start WebSocket bridge in background
npm run daemon &  # Start settlement daemon in background
npm run frontend  # Start the UI
```

-----

## Detailed Setup Guide

Follow these steps for a complete, clean setup in an environment like Google Cloud Shell.

### 1\. Prepare Environment

```bash
# Install Foundry (for Solidity)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install PNPM (for the frontend)
npm install -g pnpm

# Install and start Redis Server
sudo apt-get update && sudo apt-get install -y redis-server
sudo redis-server /etc/redis/redis.conf --daemonize yes
redis-cli ping  # <-- Must respond with PONG
```

### 2\. Configure Project

```bash
# Clone the repository and its submodules
git clone https://github.com/shinertx/bbod.git
cd bbod
git submodule update --init

# Install all project dependencies
pnpm install
pnpm --prefix frontend install
forge install

# Create and fill out your secret .env file
cp .env.example .env
nano .env # <-- Add your RPC and burner wallet private keys (PRIV)
```

-----

## Operational Flow

This is the correct sequence for deploying and running the live stack.

### 1\. Deploy Contracts

First, confirm your tests pass. Then, load your secrets and run the deployment script.

```bash
# Run the full test suite
forge test -vv --root .

# Load secrets into your terminal session
source .env

# Deploy to a temporary mainnet fork for testing
forge script script/Deploy.s.sol --fork-url $RPC --broadcast --root .

# Deploy to a live network (e.g., Mainnet or Sepolia)
# forge script script/Deploy.s.sol --rpc-url $YOUR_NETWORK_RPC --broadcast --private-key $YOUR_DEPLOYER_PRIV --root .
```

After deployment, copy the `BBOD`, `BSP`, and `ORACLE` contract addresses printed in the logs and add them to your `.env` file.

### 2\. Run Services

You need three services running concurrently. The easiest way is to use three separate terminals or a tool like `tmux`.

  * **Terminal 1 (Bridge):** `npm run ws`
  * **Terminal 2 (Daemon):** `source .env && npm run daemon`
  * **Terminal 3 (Frontend):** `npm run frontend`

### 3\. View the UI

Navigate to `http://localhost:3000` in your web browser. You should see the live blob fee updating in real-time.

-----

## Commands Reference

| Command / Script | What it does |
| :--- | :--- |
| `pnpm install` | Install Node dependencies. |
| `pnpm --prefix frontend install` | Install frontend dependencies. |
| `forge test -vv` | Run the full Solidity test suite. |
| `forge script script/Deploy.s.sol ...` | Deploy the full suite of contracts. |
| `npm run daemon` | Starts the daemon to settle rounds and manage the protocol. |
| `npm run ws` | Starts the WebSocket bridge for the frontend UI. |
| `npm run frontend` | Starts the Next.js UI for local development. |

-----

## License

This project is released under the MIT License. See individual file headers for SPDX identifiers.
