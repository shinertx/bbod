import { spawn, ChildProcessWithoutNullStreams } from "child_process";
import { ethers, TypedDataDomain, TypedDataField, Wallet } from "ethers";
import fs from "fs";
import assert from "assert";

async function waitFor(proc: ChildProcessWithoutNullStreams): Promise<void> {
  await new Promise((resolve) => {
    proc.stdout.on("data", (d: Buffer) => {
      if (d.toString().includes("Listening")) resolve(null);
    });
  });
}

async function main() {
  const anvil = spawn("anvil", ["--silent"]);
  await waitFor(anvil);

  const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
  const keys = (
    process.env.ORACLE_KEYS ||
    "0x59c6995e998f97a5a0044966f0945388cf53b6f9b3b466d4ff9969da48b50f0d"
  ).split(",");
  const wallets = keys.map((k) => new Wallet(k, provider));

  const artifact = JSON.parse(
    fs.readFileSync("out/BlobFeeOracle.sol/BlobFeeOracle.json", "utf8"),
  );
  const factory = new ethers.ContractFactory(
    artifact.abi,
    artifact.bytecode,
    wallets[0],
  );
  const oracle = await factory.deploy([wallets[0].address], 1);
  await oracle.waitForDeployment();

  const domain: TypedDataDomain = {
    name: "BlobFeeOracle",
    version: "1",
    chainId: (await provider.getNetwork()).chainId,
    verifyingContract: await oracle.getAddress(),
  };
  const types: Record<string, Array<TypedDataField>> = {
    FeedMsg: [
      { name: "fee", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
  };

  const fee = 123n;
  const message = { fee, deadline: BigInt(Math.floor(Date.now() / 1000) + 30) };
  const digest = ethers.TypedDataEncoder.hash(domain, types, message);
  const sigs = wallets.map((w) => w.signingKey.sign(digest).serialized);
  const msgs = wallets.map(() => message);
  await oracle.push(msgs, sigs);
  const last = await oracle.lastFee();
  assert.equal(last.toString(), fee.toString());

  anvil.kill();
}

main();
