import { ethers } from "ethers";
import "dotenv/config";

/*
 * ivBot – implied-volatility autopilot
 * ----------------------------------
 * Periodically updates the dynamic pricing parameter ("k") or
 * opens new option series with adjusted strike levels. The exact
 * pricing logic is application-specific – for now we keep a very
 * simple placeholder implementation that can easily be replaced
 * with a more sophisticated model later on.
 */

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const writer   = new ethers.Wallet(process.env.PRIV!, provider);

// Option desk owned by `writer`.
const desk = new ethers.Contract(
  process.env.BBOD!,
  [
    // NOTE: The contract does not currently expose a setter for `k`.
    //       If/when a method is added (e.g. `setK(uint256)`), just
    //       extend the ABI below and update the call inside `tick()`.
    "function k() view returns(uint256)",
    "function create(uint256,uint256,uint256,uint256,uint256) payable",
  ],
  writer
);

const ONE_HOUR = 60 * 60 * 1000;
const FEES: number[] = [];
const WINDOW = 12;

async function tick() {
  try {
    const fee: number = await provider.send("eth_blobBaseFee", []);
    FEES.push(fee);
    if (FEES.length > WINDOW) FEES.shift();
    if (FEES.length < WINDOW) return;

    const mean = FEES.reduce((a, b) => a + b, 0) / FEES.length;
    const variance = FEES.reduce((a, b) => a + (b - mean) ** 2, 0) / FEES.length;
    const sigma = Math.sqrt(variance);

    const currentK: bigint = await desk.k();
    const nextK = BigInt(Math.floor(sigma * 1e9));

    if (nextK !== currentK) {
      const tx = await desk.setK(nextK);
      console.log(`setK(${nextK}) → ${tx.hash}`);
    }

    // ------------------------------------------------------------------
    // 3. OPTIONAL – open a new option series every hour if none exists.
    //    This shows how the bot *could* be extended. For now we keep the
    //    logic disabled to avoid unintended side effects.
    // ------------------------------------------------------------------
    /*
    const id      = Math.floor(Date.now() / 3_600_000); // unix-hour
    const strike  = 25;             // gwei – replace with your own model
    const cap     = strike + 50;    // +50 gwei head-room
    const expiry  = Math.floor(Date.now() / 1000) + 2 * 3600; // 2 h
    const maxSold = 20;
    const margin  = ethers.parseEther("1"); // sufficiently over-collateralised

    try {
      const tx = await desk.create(id, strike, cap, expiry, maxSold, { value: margin });
      console.log(`New series ${id} opened (strike=${strike}, cap=${cap})`, tx.hash);
    } catch { /* series might already exist – ignore */ /* }
    */
  } catch (err) {
    console.error("ivBot error", err);
  }
}

setInterval(tick, ONE_HOUR);
console.log("ivBot running…"); 