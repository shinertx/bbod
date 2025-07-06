import { ethers } from "ethers";
import "dotenv/config";

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const keys = process.env.ORACLE_KEYS!.split(",");
const signers = keys.map(k => new ethers.Wallet(k, provider));

const oracle = new ethers.Contract(
  process.env.ORACLE!,
  ["function push((uint256 fee,uint256 deadline),bytes[] sigs) external"],
  signers[0]
);

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
    const deadline = Math.floor(Date.now() / 1000) + 30;
    const message = { fee, deadline };
    const sigs: string[] = [];
    for (const w of signers) {
      sigs.push(await w.signTypedData(domain, types, message));
    }
    const tx = await oracle.push(message, sigs);
    console.log(`pushed ${fee} gwei -> ${tx.hash}`);
  }

  setInterval(publish, 12_000);
  console.log("oracleBot running…");
})();
