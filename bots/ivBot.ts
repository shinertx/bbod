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

async function tick() {
  try {
    // ------------------------------------------------------------------
    // 1. Retrieve current on-chain parameter value so we can decide if an
    //    update is necessary.
    // ------------------------------------------------------------------
    const currentK: bigint = await desk.k();

    // Placeholder: naive mean-reversion towards an arbitrary target.
    const targetK = 7_000_000_000_000_000n; // 7e15 – matches default in contract.
    const delta   = (targetK - currentK) / 10n; // gentle adjustment (10% step).
    const nextK   = currentK + delta;

    // ------------------------------------------------------------------
    // 2. If contract has a setter implemented, push the new value.
    // ------------------------------------------------------------------
    // Example (commented-out until `setK(uint256)` exists on the desk):
    // const tx = await desk.setK(nextK);
    // console.log(`setK(${nextK}) → ${tx.hash}`);

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