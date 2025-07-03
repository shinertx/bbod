import { ethers } from "ethers";
import "dotenv/config";

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.RPC!);
  const wallet = new ethers.Wallet(process.env.PRIV!, provider);
  const pm = new ethers.Contract(process.env.BSP!, ["function setNextThreshold(uint256) external"], wallet);
  const fee: number = await provider.send("eth_blobBaseFee", []);
  const thr = Math.max(5, Math.min(200, Math.round(fee)));
  const tx = await pm.setNextThreshold(thr);
  console.log(`setNextThreshold(${thr}) -> ${tx.hash}`);
}

main().catch((err)=>{ console.error(err); process.exit(1); });
