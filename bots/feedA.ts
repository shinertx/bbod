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
const keys = process.env.ORACLE_KEYS!.split(",");
const signers = keys.map(k => new ethers.Wallet(k, provider));

const oracle = new ethers.Contract(
  process.env.ORACLE!,
  ["function push((uint256 fee,uint256 deadline),bytes[] sigs) external"],
  signers[0]
);

const feeGauge = new client.Gauge({ name: "oracle_fee_gwei", help: "Last fee pushed (gwei)" });

(async () => {
  const network = await provider.getNetwork();
  const domain = {
    name: "BlobFeeOracle",
    version: "1",
    chainId: Number(network.chainId),
    verifyingContract: oracle.target as string,
  };
  const types = { FeedMsg: [{ name: "fee", type: "uint256" }, { name: "deadline", type: "uint256" }] };

  async function publish() {
    try {
      const fee: number = await provider.send("eth_blobBaseFee", []);
      const deadline = Math.floor(Date.now() / 1000) + 30;
      const message = { fee, deadline };
      const sigs: string[] = [];
      for (const w of signers) {
        sigs.push(await w.signTypedData(domain, types, message));
      }
      const tx = await oracle.push(message, sigs);
      feeGauge.set(fee);
      console.log(`pushed ${fee} gwei -> ${tx.hash}`);
    } catch (err) {
      console.error("oracle push error", err);
    }
  }

  setInterval(publish, 12_000);
  console.log("feedA running…");
})();
