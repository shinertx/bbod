import { ethers } from "ethers";
import fetch from "node-fetch";
import Redis from "ioredis";
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

async function blobFeeGwei(): Promise<number> {
  try {
    return await PROVIDER.send("eth_blobBaseFee", []);
  } catch {
    const r = await fetch(process.env.BEACON!, { timeout: 1500 });
    const j = await r.json();
    return Number(j.data.blob_fee);
  }
}

(async () => {
  let lastHour = 0;
  for (;;) {
    const fee = await blobFeeGwei();
    await redis.publish("blobFee", fee.toString());

    const hr = Math.floor(Date.now()/3600_000);
    if (hr !== lastHour) {
      lastHour = hr;
      try {
        const tx = await bParimutuel.settle({ gasLimit: 120000 });
        console.log(`settle sent`, tx.hash);
      } catch(e){ console.error(`settle fail`, e); }
    }
    await new Promise(r=>setTimeout(r, 12_000));
  }
})(); 