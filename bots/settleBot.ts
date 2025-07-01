import { ethers } from "ethers";
import "dotenv/config";

/*
 * settleBot – permissionless fallback keeper
 * -----------------------------------------
 * Periodically checks whether the current parimutuel round is past its
 * settlement timestamp and, if so, calls `settle()` to earn the 0.10 % bounty.
 */

const provider = new ethers.JsonRpcProvider(process.env.RPC!);
const wallet   = new ethers.Wallet(process.env.PRIV!, provider);

const pm = new ethers.Contract(
  process.env.BSP!,
  [
    "function cur() view returns(uint256)",
    "function rounds(uint256) view returns(uint256 closeTs,uint256 hiPool,uint256 loPool,uint256 feeWei,uint256 thresholdGwei,uint256 settlePriceGwei)",
    "function settle() external",
  ],
  wallet
);

async function maybeSettle() {
  try {
    const id: bigint = await pm.cur();
    const round = await pm.rounds(id);
    const closeTs = Number(round.closeTs);
    const nowTs   = Math.floor(Date.now() / 1000);

    if (nowTs > closeTs + 12) {
      const tx = await pm.settle({ gasLimit: 200_000 });
      console.log(`settle() sent for round ${id} → ${tx.hash}`);
    }
  } catch (err) {
    // Reverts are expected if round not yet settlable; swallow them.
  }
}

setInterval(maybeSettle, 12_000);
console.log("settleBot running…"); 