import { ethers } from "ethers";
import client from "prom-client";
import "dotenv/config";

/*
 * seedBot – liquidity seeder & premium compounding helper
 * ------------------------------------------------------
 * Keeps the option desk supplied with fresh series and tops up the public
 * parimutuel pools with small amounts so that the UI always shows
 * non-empty liquidity.
 */

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const writer   = new ethers.Wallet(process.env.PRIV!, provider);

// ---------------------------------------------------------------------------
// Contract ABIs (only the functions we call).
// ---------------------------------------------------------------------------
const desk = new ethers.Contract(
  process.env.BBOD!,
  [
    "function premium(uint256,uint256) view returns(uint256)",
    "function create(uint256,uint256,uint256,uint256,uint256) payable",
  ],
  writer
);

const pm = new ethers.Contract(
  process.env.BSP!,
  [
    "function commit(bytes32) payable",
    "function reveal(uint8,bytes32)"
  ],
  writer
);

// ---------------------------------------------------------------------------
// Metrics (Prometheus)
// ---------------------------------------------------------------------------
const stakeGauge = new client.Gauge({ name: "seedbot_stake_eth", help: "ETH sent as seed liquidity" });
const seriesGauge = new client.Gauge({ name: "seedbot_series", help: "Last option series id opened" });

// Export all metrics on :9464/metrics when launched with `node exporter` image.
if (process.env.METRICS_PORT) {
  const http = await import("http");
  const port = Number(process.env.METRICS_PORT);
  const server = http.createServer(async (_, res) => {
    res.writeHead(200, { "Content-Type": client.register.contentType });
    res.end(await client.register.metrics());
  });
  server.listen(port, () => console.log(`prom metrics on :${port}`));
}

// ---------------------------------------------------------------------------
// Main loop – once per hour.
// ---------------------------------------------------------------------------
async function tick(): Promise<void> {
  // Series id = unixHour (same epoch as on-chain contracts)
  const id = Math.floor(Date.now() / 3_600_000);
  const strike = 25;                          // gwei – placeholder
  const cap    = strike + 25;                 // hedge head-room (strike+25 gwei)
  const expiry = Math.floor(Date.now() / 1000) + 2 * 3600; // 2 h
  const maxSold = 20;

  try {
    // Quote and open new series
    const premWei: bigint = await desk.premium(strike, expiry);
    console.log(`premium for strike ${strike} →`, ethers.formatEther(premWei), "ETH");

    const margin = ethers.parseEther("1"); // over-collateralise generously
    const tx = await desk.create(id, strike, cap, expiry, maxSold, { value: margin });
    await tx.wait();
    console.log(`series ${id} opened (strike=${strike}, cap=${cap})`);
    seriesGauge.set(id);
  } catch {
    // If the series already exists the `create` call reverts – ignore.
  }

  // Seed the parimutuel pools with tiny stakes using commit-reveal.
  const stake = ethers.parseEther("0.05");
  try {
    const saltHi = ethers.randomBytes(32);
    const saltLo = ethers.randomBytes(32);
    const hHi = ethers.solidityPackedKeccak256([
      "address",
      "uint8",
      "bytes32"
    ], [writer.address, 0, saltHi]);
    const hLo = ethers.solidityPackedKeccak256([
      "address",
      "uint8",
      "bytes32"
    ], [writer.address, 1, saltLo]);

    await (await pm.commit(hHi, { value: stake })).wait();
    await (await pm.commit(hLo, { value: stake })).wait();
    stakeGauge.inc(Number(ethers.formatEther(stake)) * 2);
    console.log(`seeded pools with 0.05 ETH on both sides`);

    setTimeout(async () => {
      try {
        await (await pm.reveal(0, saltHi)).wait();
        await (await pm.reveal(1, saltLo)).wait();
        console.log(`revealed seed bets`);
      } catch (err) {
        console.error("seed reveal error", err);
      }
    }, 305_000);
  } catch (err) {
    console.error("seed liquidity error", err);
  }
}

setInterval(tick, 55 * 60 * 1000); // every ~55 minutes
console.log("seedBot running…"); 