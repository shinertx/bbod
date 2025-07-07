# Blob Edge Stack (BBOD + BSP)

Blob Edge Stack is a decentralized derivatives suite built around Ethereum's EIP-4844 blob base fee. It contains two main on-chain systems and a collection of off-chain bots and daemons:

- **BBOD** – `BlobOptionDesk`: fully collateralized options on future blob fees.
- **BSP** – `CommitRevealBSP`: hourly betting market with commit-reveal settlement.
- **BlobFeeOracle** – lightweight push oracle for blob fee observations.

The repository also ships monitoring and automation tools for production deployment.

---

## Repository Layout

- **`contracts/`** – Solidity contracts for the oracle, option desk and parimutuel vaults.
- **`daemon/`** – Off-chain TypeScript services: `blobDaemon.ts` to fetch blob fees and settle BSP rounds, `wsBridge.ts` to relay Redis pub/sub messages to WebSocket clients, and `oracleBot.ts` to sign and push fees.
- **`bots/`** – Operational keepers and market bots:
  - `ivBot.ts` – placeholder implied-volatility updater for BBOD.
  - `seedBot.ts` – opens option series and seeds pools with small stakes.
  - `settleBot.ts` – permissionless fallback for settling BSP rounds.
  - `thresholdBot.ts` – automatically adjusts the BSP threshold from recent fees.
- **`script/`** – Forge deployment script `Deploy.s.sol` plus helper scripts (`settle.ts`, `flashBundle.ts`).
- **`test/`** – Foundry test suite covering edge cases and fuzz scenarios.
- **`frontend/`** – Minimal Next.js dashboard for live metrics.
- **`docker/`** – Example compose file for Prometheus/Grafana monitoring.

---

## Contracts Overview

| Contract          | Purpose                                                                |
| ----------------- | ---------------------------------------------------------------------- |
| `BlobFeeOracle`   | 3-of-N push oracle that records the fee signed by a quorum of feeders. |
| `BlobOptionDesk`  | Fully collateralized call options on future blob fees.                 |
| `CommitRevealBSP` | Hourly parimutuel market using commit-reveal mechanics.                |
| `BaseBlobVault`   | Shared event helpers for settlement.                                   |
| `IBlobBaseFee`    | Interface used by both BBOD and BSP to query the fee.                  |

### Key Parameters

- **BlobFeeOracle** – successive fee pushes may not deviate by more than 2x.
- **CommitRevealBSP** – `REVEAL_TIMEOUT` of 15 minutes prevents threshold-freeze. `THRESHOLD_REVEAL_TIMEOUT` of 1 hour falls back to the previous threshold if unrevealed.
- **BlobOptionDesk** – premium scale `k` defaults to `7e13`; margin withdrawal is possible after `GRACE_PERIOD` (1 day).

## Environment Variables

Create a `.env` file (see `.env.example`) and populate the following variables:

| Name           | Purpose                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------- |
| `RPC`          | RPC URL used by bots and tests                                                           |
| `PRIV`         | Private key for deployments and bot accounts                                             |
| `ORACLE_KEYS`  | Comma separated private keys used by `oracleBot.ts` and feed bots for EIP-712 signatures |
| `ORACLE`       | Address of the deployed `BlobFeeOracle`                                                  |
| `BLOB_ORACLE`  | Same as `ORACLE` for forge scripts                                                       |
| `BSP`          | Address of the deployed `CommitRevealBSP`                                                |
| `BBOD`         | Address of the deployed `BlobOptionDesk`                                                 |
| `REDIS`        | Redis connection string (for daemon and WebSocket bridge)                                |
| `BEACON`       | Fallback beacon API endpoint for blob fees                                               |
| `WS_PORT`      | Port for the local WebSocket bridge                                                      |
| `METRICS_PORT` | Port to expose Prometheus metrics                                                        |

Example:

```bash
RPC=https://mainnet.infura.io/v3/YOUR_KEY
PRIV=0xYOUR_PRIVATE_KEY
ORACLE_KEYS=0xKEY1,0xKEY2,0xKEY3
ORACLE=0xORACLE_ADDRESS
BLOB_ORACLE=0xORACLE_ADDRESS
BSP=0xBSP_ADDRESS
BBOD=0xBBOD_ADDRESS
REDIS=redis://localhost:6379
BEACON=http://localhost:5052/eth/v1/debug/beacon/blob_fee
WS_PORT=6380
METRICS_PORT=9464
```

---

## Setup

1. **Clone the repo and submodules**
   ```bash
   git clone https://github.com/shinertx/bbod.git
   cd bbod
   git submodule update --init
   cp .env.example .env  # edit with your values
   ```
2. **Install dependencies**
   ```bash
   npm install -g pnpm
   pnpm install
   pnpm --prefix frontend install
   ```
3. **Run tests** (requires Foundry)
   ```bash
   forge test -vv
   ```
4. **Deploy contracts**
   ```bash
   source .env
   forge script script/Deploy.s.sol --fork-url $RPC --broadcast
   # record the BBOD/BSP/oracle addresses and update .env
   ```
5. **Start daemons/bots**
   ```bash
   pnpm ts-node daemon/wsBridge.ts
   pnpm ts-node daemon/blobDaemon.ts
   pnpm ts-node daemon/oracleBot.ts         # run on multiple machines for liveness
   pnpm ts-node bots/thresholdBot.ts
   pnpm ts-node bots/settleBot.ts
   pnpm ts-node bots/seedBot.ts
   ```
   The oracleBot and feed bots sign each message with the keys in `ORACLE_KEYS` using EIP-712.

---

## Production Notes

For a resilient deployment run at least two oracle bot instances (on different providers) so the oracle continues pushing data if one fails. Keep the `settleBot` and `thresholdBot` online to ensure BSP rounds progress and thresholds track the market. Use `docker-compose` to start Prometheus and Grafana for monitoring. Expose metrics from bots via `METRICS_PORT` and add alerts for stalled feeds or missed settlements.

All contracts are permissionless once deployed but rely on timely feeds to remain safe. The oracle can be overridden via timelock only if signers stop pushing for a full day. Carefully manage private keys and RPC reliability to avoid stuck rounds.

**Risk Warning:** Options and parimutuel betting are inherently risky. Smart contract bugs, oracle failures or extreme volatility could lead to loss of funds. Run extensive tests on a fork before using real value.

---

## FAQ & Troubleshooting

**Q:** Tests fail with `forge: command not found`
**A:** Install Foundry (`curl -L https://foundry.paradigm.xyz | bash && foundryup`).

**Q:** Bots cannot connect to Redis.
**A:** Check that Redis is running and `REDIS` in `.env` points to the correct host.

**Q:** `forge script` cannot find `BLOB_ORACLE`.
**A:** Ensure the oracle address is set in `.env` as both `ORACLE` and `BLOB_ORACLE` before running the deploy script.

**Q:** The UI shows no data.
**A:** Confirm the WebSocket bridge (`wsBridge.ts`) is running and that oracle bots are publishing fees to Redis.

---

## Contributing

1. Fork the repository and create a feature branch.
2. Follow the guidelines in `AGENTS.md` – all changes must pass `forge test -vv` and any lint/format checks.
3. Submit a pull request with a clear description of your changes and test evidence.
4. Maintain backward compatibility when touching on-chain code and document any new parameters or risks.

## Security: How to protect your operator private key

Never commit private keys or plaintext mnemonics. Use a hardware wallet or encrypted secret manager for production bots. Environment files should only reference key URIs, and access should be limited.

---

## License

This project is licensed under the MIT License. See each file for its SPDX identifier.
