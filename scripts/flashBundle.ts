import { ethers } from "ethers";
import { FlashbotsBundleProvider, FlashbotsBundleResolution } from "@flashbots/ethers-provider-bundle";
import "dotenv/config";

async function main() {
  if (process.argv.length < 3) {
    console.error("usage: ts-node flashBundle.ts <signedUserTxHex>");
    process.exit(1);
  }

  const signedUserTx = process.argv[2];
  const provider = new ethers.JsonRpcProvider(process.env.RPC!);

  // Ephemeral relayer identity – can be random because relay identifies bundles by tx content.
  const authSigner = ethers.Wallet.createRandom();
  const flashbots = await FlashbotsBundleProvider.create(provider, authSigner);

  const wallet = new ethers.Wallet(process.env.PRIV!, provider);
  const pm = new ethers.Contract(process.env.BSP!, ["function settle()"], wallet);

  const settleTxReq = await pm.populateTransaction.settle();

  // Build bundle: [userTx, settleTx]
  const bundle = [
    { signedTransaction: signedUserTx },
    { signer: wallet, transaction: { ...settleTxReq, gasLimit: 200_000 } },
  ];

  const blockNumber = await provider.getBlockNumber();
  const targetBlock = blockNumber + 1;

  const res = await flashbots.sendBundle(bundle, targetBlock);
  const waitRes = await res.wait();

  console.log("bundle result:", FlashbotsBundleResolution[waitRes]);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
}); 