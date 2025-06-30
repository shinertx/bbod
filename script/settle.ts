import { ethers } from "ethers";
import "dotenv/config";
const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet   = new ethers.Wallet(process.env.PRIV!, provider);
const bsp      = new ethers.Contract(process.env.BSP!, ["function settle()"], wallet);

(async () => {
  const tx = await bsp.settle();
  console.log("settle tx", tx.hash);
})(); 