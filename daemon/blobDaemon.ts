import { ethers } from "ethers";
import fetch from "node-fetch";
import Redis from "ioredis";
import { createServer } from "http";
import * as dotenv from "dotenv";
dotenv.config();

const PROVIDER = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet = new ethers.Wallet(process.env.PRIV!, PROVIDER);
const bParimutuel = new ethers.Contract(
  process.env.BSP!,
  ["function settle() external"],
  wallet
);

const redis = new Redis(process.env.REDIS || "redis://localhost:6379");

// expose health endpoint
const health = createServer((_, res) => { res.writeHead(200); res.end("ok"); });
health.listen(Number(process.env.METRICS_PORT || 9464));

async function blobFeeGwei(): Promise<number> {
  try {
    return await PROVIDER.send("eth_blobBaseFee", []);
  } catch (e) {
    console.error("RPC blob fee fetch failed", e);
    try {
      const r = await fetch(process.env.BEACON!, { timeout: 1500 });
      const j = await r.json();
      return Number(j.data.blob_fee);
    } catch (err) {
      console.error("Beacon fee fetch failed", err);
      throw err;
    }
  }
}

(async () => {
  let lastHour = 0;
  let lastFee = 0;
  for (;;) {
    let fee;
    try {
      fee = await blobFeeGwei();
      lastFee = fee;
    } catch (err) {
      console.error("blob fee fetch failed", err);
      fee = lastFee;
    }
    await redis.publish("blobFee", fee.toString());

    const hr = Math.floor(Date.now()/3600_000);
    if (hr !== lastHour) {
      try {
        const tx = await bParimutuel.settle({ gasLimit: 200_000 });
        console.log(`settle sent`, tx.hash);

        // broadcast next threshold for commitRevealBot
        await redis.publish("nextThreshold", fee.toString());

        lastHour = hr; // update only on success
      } catch (e) {
        console.error("settle fail, retrying in 15s", e);
        await new Promise(r => setTimeout(r, 15_000));
      }
    }
    await new Promise(r=>setTimeout(r, 12_000));
  }
})(); 