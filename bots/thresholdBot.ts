import { ethers } from "ethers";
import Redis from "ioredis";
import "dotenv/config";

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet   = new ethers.Wallet(process.env.PRIV!, provider);

const pm = new ethers.Contract(
  process.env.BSP!,
  ["function setNextThreshold(uint256) external"],
  wallet
);

const WINDOW = 3600; // 1-hour rolling window
let fees: number[] = [];

provider.on("block", async (bn: number) => {
  try {
    const fee: number = await provider.send("eth_blobBaseFee", []);
    fees.push(fee);
    // keep at most WINDOW/12 samples (≈1 h)
    fees = fees.slice(-Math.floor(WINDOW / 12));
    const sorted = [...fees].sort((a, b) => a - b);
    const med = sorted[Math.floor(sorted.length / 2)];
    const next = Math.max(5, Math.min(200, Math.round(med)));

    if (bn % 300 === 0) {
      const tx = await pm.setNextThreshold(next);
      console.log(`setNextThreshold(${next}) → ${tx.hash}`);
    }
  } catch (err) {
    console.error("thresholdBot error", err);
  }
});

console.log("thresholdBot running…"); 