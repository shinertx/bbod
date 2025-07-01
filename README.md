# Blob Edge Stack

A small suite of contracts and helpers around Ethereum’s blob base fee.

- **BBOD** – Blob‑Base fixed‑strike call options
- **BSP** – Hourly HI/LO parimutuel blob‑fee pools

Everything is deployable by a single EOA with ≤0.1 ETH gas and requires no off‑chain trust.

---

## Overview

The stack offers two complementary primitives:

### Blob Option Desk (BBOD)
A vault where a writer escrows ETH to sell European call options on the blob base fee. Premiums are priced by a simple volatility formula and payouts are capped by the writer’s margin.

### Blob Spread Pools (BSP)
Hourly parimutuel rounds where users bet on whether the next fee tick ends “High” or “Low” versus a threshold. Winners split the pool minus a small rake.

Both rely on a lightweight Blob Fee Oracle that aggregates signer submissions every 12‑second slot. Once a quorum of signatures is provided, the oracle stores the arithmetic mean as the canonical fee for that slot.

---

## Core Concepts

### Hedging vs. Speculating

- **Use BBOD** when you want fixed‑strike exposure and guaranteed collateral.
- **Use BSP** for short‑term speculation on the hourly fee direction.

### Oracle Signers

Any set of up to 256 signers can push observations. A majority of signatures finalises the fee and triggers the `NewFee` event.  
_Source: `BlobFeeOracle.sol` lines 17‑27._

### Settlement Bounties

Both BBOD and BSP award a tiny bounty (0.10 %) to whoever calls `settle()` once an epoch is finished.  
_Example: `BlobParimutuel.sol` lines 32‑33._

---

## Directory Structure

| Folder         | Purpose                                                                                  |
|----------------|------------------------------------------------------------------------------------------|
| `contracts/`   | Solidity sources for BBOD, BSP, the oracle and helper vaults.                           |
| `script/`      | Forge deployment script and small Node helpers.                                         |
| `daemon/`      | TypeScript daemons: fetch blob fee, settle rounds, and relay data via WebSocket.        |
| `test/`        | Foundry tests covering options logic, parimutuel edge cases and payout caps.            |
| `bots/`        | Example automation bots (oracle feeders, seeding liquidity, etc.).                      |
| `frontend/`    | Minimal Next.js UI showing the current blob fee.                                        |
| `docker/`      | Docker Compose stack with Prometheus, Grafana and Redis.                                |
| `prometheus/`  | Prometheus scrape configuration.                                                        |

---

## Setup

### Clone the repo

```sh
git clone https://github.com/you/blob-edge-stack
cd blob-edge-stack
```

### Prepare environment variables

```sh
cp .env.example .env    # edit RPC, PRIV and others
```

Example variables are shown in `.env.example`:
```
RPC=https://mainnet.infura.io/v3/YOUR_KEY
PRIV=0xYOUR_PRIVATE_KEY
BSP=0xBSP_CONTRACT_AFTER_DEPLOY
REDIS=redis://localhost:6379
BEACON=http://localhost:5052/eth/v1/debug/beacon/blob_fee
```
Optionally export `BLOB_ORACLE` if deploying with a pre-existing oracle.

### Install dependencies

```sh
pnpm install        # installs root and daemon dependencies
pnpm --prefix frontend install   # install frontend deps
```

### Install Foundry

```sh
foundryup           # installs forge, cast, anvil
```

### Run the tests

```sh
forge test -vv
```

---

## Deploy & Run

### Deploy contracts

```sh
source .env
forge script script/Deploy.s.sol \
  --fork-url "$RPC" \
  --broadcast \
  --private-key "$PRIV"
```

Deployment logs print the addresses of BBOD and BSP:  
_See: `Deploy.s.sol` lines 16‑20._  
Set `BSP` in `.env` to the printed parimutuel address if not already.

### Start daemons

In one terminal:
```sh
npm run daemon      # runs daemon/blobDaemon.ts
```
This daemon fetches the blob fee and periodically settles the current round.  
It relies on the environment variables used in the code:  
_See: `blobDaemon.ts` lines 7‑18._

In another terminal:
```sh
npm run ws          # runs daemon/wsBridge.ts
```
This bridges the Redis feed to WebSocket clients on port 6380 by default:  
_See: `wsBridge.ts` lines 5‑12._

### Launch the UI (optional)

```sh
npm run frontend    # starts Next.js on http://localhost:3000
```
The frontend displays the live blob fee streamed via WebSocket.

---

## Commands Reference

| Command / Script                                                     | What it does                                                      |
|---------------------------------------------------------------------|-------------------------------------------------------------------|
| `pnpm install`                                                      | Install Node dependencies.                                        |
| `pnpm --prefix frontend install`                                    | Install frontend dependencies.                                    |
| `forge test -vv`                                                    | Run the full Solidity test suite.                                 |
| `forge script script/Deploy.s.sol --fork-url $RPC --broadcast --private-key $PRIV` | Deploy BBOD and BSP contracts.                    |
| `npm run daemon` → `tsx daemon/blobDaemon.ts`                       | Fetch blob fee, settle hourly rounds, publish to Redis.           |
| `npm run ws` → `tsx daemon/wsBridge.ts`                             | WebSocket relay exposing blobFee events.                          |
| `npm run frontend` → `pnpm --prefix frontend dev`                   | Start the Next.js UI for local development.                       |
| `ts-node script/settle.ts`                                          | One-off script to manually call `settle()` (uses $RPC, $PRIV and $BSP). |
| `ts-node scripts/flashBundle.ts <signedUserTx>`                     | Submit a Flashbots bundle with a user transaction and a `settle()` call. |

The available npm scripts are defined in `package.json` lines 4‑8.

---

## Operational Flow

1. **Deploy or point to an existing Blob Fee Oracle.**
2. **Run the deployment script to create BBOD and BSP.**
3. **Keep the daemon running** so each hourly round settles automatically.
4. **Optionally run auxiliary bots** (`bots/`) for seeding liquidity or updating thresholds.
5. **View real‑time metrics** via Prometheus/Grafana if the Docker stack is launched.

The above information is derived from the repository’s sources and config files:

- Environment template: `.env.example`
- Foundry settings: `foundry.toml`
- Daemon configuration: `daemon/blobDaemon.ts` and `daemon/wsBridge.ts`

---

This README consolidates the entire workflow—clone, test, deploy and operate—into a single reference. Use it as the starting point for all development and production setups.
