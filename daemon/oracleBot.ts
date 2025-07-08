import { ethers } from "ethers";
import "dotenv/config";
import client from "prom-client";

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const keys = process.env.ORACLE_KEYS!.split(",");
const signers = keys.map(k => new ethers.Wallet(k, provider));

const oracle = new ethers.Contract(
  process.env.ORACLE!,
  ["function push((uint256 fee,uint256 deadline),bytes[] sigs) external"],
  signers[0]
);

const feeGauge = new client.Gauge({ name: "oracle_last_fee_gwei", help: "Last fee pushed to oracle" });
const skipCounter = new client.Counter({ name: "oracle_skip_guardrail_total", help: "Number of push attempts skipped due to guardrail" });
client.collectDefaultMetrics();

let lastFee = 0;

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
    const fee: number = await provider.send("eth_blobBaseFee", []);
    if (lastFee !== 0 && fee > lastFee * 2) {
      console.warn(`[oracleBot] Skip push: fee ${fee} > 2× previous ${lastFee}`);
      skipCounter.inc();
      return;
    }
    const deadline = Math.floor(Date.now() / 1000) + 30;
    const message = { fee, deadline };
    const sigs: string[] = [];
    for (const w of signers) {
      sigs.push(await w.signTypedData(domain, types, message));
    }
    const tx = await oracle.push(message, sigs);
    console.log(`pushed ${fee} gwei -> ${tx.hash}`);
    lastFee = fee;
    feeGauge.set(fee);
  }

  setInterval(publish, 12_000);
  console.log("oracleBot running…");
})();

// Expose metrics on configured port or 9464 default.
import http from "http";
const port = Number(process.env.METRICS_PORT || 9464);
http.createServer(async (_req, res) => {
  res.writeHead(200, { "Content-Type": client.register.contentType });
  res.end(await client.register.metrics());
}).listen(port, () => console.log(`[oracleBot] metrics on ${port}`));
