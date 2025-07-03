import { ethers } from "ethers";
import Redis from "ioredis";
import * as dotenv from "dotenv";
dotenv.config();

const redis = new Redis(process.env.REDIS || "redis://localhost:6379");
const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet   = new ethers.Wallet(process.env.PRIV!, provider);

const pm = new ethers.Contract(
  process.env.BSP!,
  [
    "event NewRound(uint256 indexed round,uint256 closeTs,uint256 revealTs,uint256 thresholdGwei)",
    "event Settled(uint256 indexed round,uint256 feeGwei,uint256 rakeWei)",
    "function commit(bytes32) external",
    "function reveal(uint256,uint256) external"
  ],
  wallet
);

let latestFee = 0;
let nonce = 0;
const pending: Record<number,{thr:number,nonce:number}> = {};

redis.subscribe("blobFee", "nextThreshold");
redis.on("message", (_, msg) => {
  if (_ === "blobFee") latestFee = Number(msg);
  if (_ === "nextThreshold") latestFee = Number(msg);
});

pm.on("NewRound", async (id: bigint) => {
  if (!latestFee) return;
  nonce += 1;
  const thr = latestFee;
  const h = ethers.solidityPackedKeccak256(["uint256","uint256"],[thr, nonce]);
  try {
    await (await pm.commit(h)).wait();
    pending[Number(id)+1] = { thr, nonce };
    console.log(`commit round ${Number(id)+1} thr=${thr}`);
  } catch (e) {
    console.error("commit error", e);
  }
});

pm.on("Settled", async (id: bigint) => {
  const data = pending[Number(id)+1];
  if (!data) return;
  try {
    await (await pm.reveal(data.thr, data.nonce)).wait();
    delete pending[Number(id)+1];
    console.log(`reveal round ${Number(id)+1} thr=${data.thr}`);
  } catch (e) {
    console.error("reveal error", e);
  }
});

console.log("commitRevealBot running…");
