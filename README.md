# Blob Edge Stack (BBOD + BSP)

Blob Edge Stack is a collection of on-chain contracts and off-chain services that allow trading of options on the EIP-4844 blob base fee and a commit-reveal parimutuel market. Everything is designed to run permissionlessly with simple bots and monitoring.

---

## Core Concepts

- **BlobFeeOracle** – push oracle where multiple feeders sign the blob base fee using EIP-712.
- **BlobOptionDesk (BBOD)** – fully collateralized options paying out on future blob base fees.
- **CommitRevealBSP (BSP)** – hourly betting rounds with commit-reveal to prevent copy trading.
- **BaseBlobVault / IBlobBaseFee** – shared helpers for querying the fee and emitting events.
- **Off-chain bots** – daemons keep the oracle updated, settle rounds and publish metrics through Redis.

---

## Directory Layout

| Path | Description |
|------|-------------|
| `contracts/` | Solidity sources for the oracle, option desk and parimutuel vaults |
| `daemon/` | Long running bots (`blobDaemon.ts`, `oracleBot.ts`, `wsBridge.ts`) |
| `bots/` | Keeper scripts such as `seedBot.ts`, `thresholdBot.ts`, `settleBot.ts` |
| `script/` | Forge deploy script (`Deploy.s.sol`) and helpers (`settle.ts`) |
| `scripts/` | Operational tools (`SafeDeploy.ts`, `flashBundle.ts`, `setThreshold.ts`) |
| `frontend/` | Minimal Next.js dashboard |
| `docker/` | Prometheus/Grafana setup |
| `ops/` | Operational docs (`GO_LIVE_CHECKLIST.md`, `KILLSWITCH.md` etc.) |
| `test/` | Foundry tests and fuzzing suites |
| `out/` | Compiled contract artifacts |

---

## Environment Variables

Create a `.env` file from `.env.example` and fill the following fields:

| Name | Purpose |
|------|---------|
| `RPC` | RPC endpoint for scripts and bots |
| `PRIV` | Operator private key |
| `ORACLE_KEYS` | Comma separated private keys used by `oracleBot.ts` |
| `BLOB_ORACLE` / `ORACLE` | Address of the deployed `BlobFeeOracle` |
| `BSP` | Deployed `CommitRevealBSP` address |
| `BBOD` | Deployed `BlobOptionDesk` address |
| `NEXT_PUBLIC_BSP` | BSP address for the frontend |
| `NEXT_PUBLIC_BBOD` | BBOD address for the frontend |
| `REDIS` | Redis connection string |
| `BEACON` | Beacon node endpoint as blob fee fallback |
| `NEXT_PUBLIC_WS` | WebSocket URL for the bridge |
| `WS_PORT` | Local WebSocket bridge port |
| `METRICS_PORT` | Port exposing Prometheus metrics |
| `NEXT_PUBLIC_ALERT` | Optional alert banner shown in the UI |

---

## Local Development Setup

```bash
# clone repo and submodules
git clone https://github.com/shinertx/bbod.git
cd bbod && git submodule update --init
cp .env.example .env  # edit with your values

# install dependencies
npm install -g pnpm
pnpm install
pnpm --prefix frontend install
```

Run `forge test -vv` once Foundry is installed to ensure everything compiles.

---

## Quick Start (Testnet)

1. Export your variables: `source .env`
2. Deploy contracts:
   ```bash
   forge script script/Deploy.s.sol --fork-url $RPC --broadcast
   ```
   Record the addresses and update `.env` and `frontend/.env` accordingly.
3. Start services in separate terminals:
   ```bash
   pnpm ts-node daemon/wsBridge.ts
   pnpm ts-node daemon/blobDaemon.ts
   pnpm ts-node daemon/oracleBot.ts    # run on multiple machines if possible
   pnpm ts-node bots/thresholdBot.ts
   pnpm ts-node bots/seedBot.ts
   pnpm ts-node bots/settleBot.ts
   ```
4. Launch the frontend with `pnpm --prefix frontend dev` and navigate to `http://localhost:3000`.

---

## Commands Reference

| Command | Purpose |
|---------|---------|
| `pnpm daemon` | Start `blobDaemon.ts` |
| `pnpm ws` | Start WebSocket bridge |
| `pnpm --prefix frontend dev` | Run the Next.js UI |
| `pnpm lint` | Run ESLint (requires config) |
| `pnpm format` | Format code with Prettier |
| `forge test -vv` | Run Foundry tests |
| `forge script script/Deploy.s.sol --fork-url $RPC --broadcast` | Deploy contracts |
| `pnpm ts-node scripts/setThreshold.ts` | Manually update next BSP threshold |

---

## Production Checklist & Liveness

Before going live review `ops/GO_LIVE_CHECKLIST.md`:
- 3 independent oracle bots online
- commitRevealBot, daemon and settleBot under a supervisor (PM2/systemd)
- Safe wallets funded with at least 8 ETH for gas
- Contracts verified on Etherscan
- Frontend rebuilt with correct `NEXT_PUBLIC_*` vars

Monitor bots via Prometheus/Grafana (`docker-compose` in `docker/`). Run a secondary daemon as described in `ops/DAEMON_BACKUP.md` and expose health endpoints on `METRICS_PORT`.

---

## Post-Deploy Actions

- Call `scripts/setThreshold.ts` after each settlement or schedule it via cron.
- Verify contracts on Etherscan and publish artifact links.
- Update the frontend environment (`NEXT_PUBLIC_*`) and redeploy.

---

## Risk Warnings & Kill-Switch

Smart contract bugs or oracle downtime can lead to lost funds or stuck rounds. Review `ops/KILLSWITCH.md` for emergency steps:
1. Stop all daemons and bots.
2. Disable or redeploy the frontend with `NEXT_PUBLIC_ALERT` set.
3. Notify users through social channels.

Use hardware wallets and limit access to the private keys listed in `.env`.

---

## Upgrade Path

Contracts are not upgradeable. New versions require a fresh deployment followed by updating bot configs and the frontend addresses. Keep previous deployments accessible for audits and historical reference.

---

## Contributing & FAQ

See `AGENTS.md` for PR requirements. All changes should come with `forge test -vv` output and linter/formatting results.

**Q:** Tests fail with `forge: command not found`
**A:** Install Foundry via `curl -L https://foundry.paradigm.xyz | bash && foundryup` (or your package manager).

**Q:** Bots cannot connect to Redis
**A:** Ensure `REDIS` in `.env` points to a running instance.

**Q:** The UI shows no data
**A:** Check that `wsBridge.ts` is running and oracle bots are publishing fees.

---

## License

This project is licensed under the MIT License. See individual files for their SPDX identifiers.
