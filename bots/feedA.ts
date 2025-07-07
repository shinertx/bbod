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
  ["function push((uint256 fee,uint256 deadline),bytes[] sigs) external"],
  wallet
);

let domain: any;
const types = { FeedMsg: [{ name: "fee", type: "uint256" }, { name: "deadline", type: "uint256" }] };

(async () => {
  const net = await provider.getNetwork();
  domain = {
    name: "BlobFeeOracle",
    version: "1",
    chainId: Number(net.chainId),
    verifyingContract: oracle.target as string,
  };
})();

const feeGauge = new client.Gauge({ name: "oracle_fee_gwei", help: "Last fee pushed (gwei)" });

async function publish() {
  try {
    const fee: number = await provider.send("eth_blobBaseFee", []);
    const message = { fee, deadline: Math.floor(Date.now() / 1000) + 30 };
    const sig = await wallet.signTypedData(domain, types, message);
    const tx = await oracle.push(message, [sig]);
    feeGauge.set(fee);
    console.log(`pushed ${fee} gwei -> ${tx.hash}`);
  } catch (err) {
    console.error("oracle push error", err);
  }
}

setInterval(publish, 12_000);
console.log("feedA running…"); 