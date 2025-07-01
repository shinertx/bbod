import { ethers } from "ethers";
import client from "prom-client";
import "dotenv/config";

/*
 * feedA – push-oracle feeder
 * -------------------------
 * Submits a blob fee observation every 12 seconds. Run on a separate
 * machine / RPC key. Identical to `feedB.ts` except for environment
 * variables.
 */

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet   = new ethers.Wallet(process.env.PRIV!, provider);

const oracle = new ethers.Contract(
  process.env.ORACLE!,
  ["function push(uint256 feeGwei) external"],
  wallet
);

const feeGauge = new client.Gauge({ name: "oracle_fee_gwei", help: "Last fee pushed (gwei)" });

async function publish() {
  try {
    const fee: number = await provider.send("eth_blobBaseFee", []);
    await oracle.push(fee);
    feeGauge.set(fee);
    console.log(`pushed ${fee} gwei`);
  } catch (err) {
    console.error("oracle push error", err);
  }
}

setInterval(publish, 12_000);
console.log("feedA running…"); 