import { ethers } from "ethers";
import { EthersAdapter, SafeAccountConfig, SafeFactory } from "@safe-global/safe-core-sdk";
import * as dotenv from "dotenv";
import fs from "fs";
import path from "path";

dotenv.config();

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.RPC!);
  const signer = new ethers.Wallet(process.env.PRIV!, provider);
  const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });

  const factory = await SafeFactory.create({ ethAdapter });
  const safe = await factory.connectSafe(process.env.SAFE_ADDRESS!);

  const Oracle = await (new ethers.ContractFactory(
    (await import("../out/BlobFeeOracle.sol/BlobFeeOracle.json")).abi,
    (await import("../out/BlobFeeOracle.sol/BlobFeeOracle.json")).bytecode,
    signer
  )).deploy([]);
  await Oracle.waitForDeployment();

  const Desk = await (new ethers.ContractFactory(
    (await import("../out/BlobOptionDesk.sol/BlobOptionDesk.json")).abi,
    (await import("../out/BlobOptionDesk.sol/BlobOptionDesk.json")).bytecode,
    signer
  )).deploy(await Oracle.getAddress());
  await Desk.waitForDeployment();

  const BSP = await (new ethers.ContractFactory(
    (await import("../out/CommitRevealBSP.sol/CommitRevealBSP.json")).abi,
    (await import("../out/CommitRevealBSP.sol/CommitRevealBSP.json")).bytecode,
    signer
  )).deploy(await Oracle.getAddress());
  await BSP.waitForDeployment();

  const envPath = path.resolve(__dirname, "../.env");
  fs.appendFileSync(envPath, `\nORACLE=${await Oracle.getAddress()}\nBBOD=${await Desk.getAddress()}\nBSP=${await BSP.getAddress()}\n`);
  console.log("Oracle", await Oracle.getAddress());
  console.log("Desk", await Desk.getAddress());
  console.log("BSP", await BSP.getAddress());
}

main().catch((e)=>{ console.error(e); process.exit(1); });
