/**
 * bridge-to-l2.ts — Deposit ETH from L1 (Sepolia) to the L2 deployer account so it can pay for
 * the L2 governance deployment. Idempotent-ish: if the L2 balance is already >= TARGET, it exits.
 *
 * Env:
 *   PRIVATE_KEY   deployer key (funds both the L1 source and the L2 recipient)
 *   L1_RPC        Sepolia RPC
 *   L2_RPC        ZKsync Era testnet RPC
 *   BRIDGE_AMOUNT ETH amount to deposit (default 0.02)
 *   BRIDGE_TARGET minimum L2 balance below which we deposit (default = BRIDGE_AMOUNT)
 */
import { Provider, Wallet, utils } from "zksync-ethers";
import { ethers } from "ethers";

async function main() {
  const pk = req("PRIVATE_KEY");
  const l1Rpc = req("L1_RPC");
  const l2Rpc = req("L2_RPC");
  const amount = ethers.parseEther(process.env.BRIDGE_AMOUNT || "0.02");
  const target = ethers.parseEther(process.env.BRIDGE_TARGET || process.env.BRIDGE_AMOUNT || "0.02");

  const l2 = new Provider(l2Rpc);
  const l1 = new ethers.JsonRpcProvider(l1Rpc);
  const wallet = new Wallet(pk, l2, l1);

  const before = await l2.getBalance(wallet.address);
  console.log(`L2 balance of ${wallet.address}: ${ethers.formatEther(before)} ETH`);
  if (before >= target) {
    console.log("L2 balance already sufficient; skipping deposit.");
    return;
  }

  const l1Bal = await l1.getBalance(wallet.address);
  console.log(`L1 balance: ${ethers.formatEther(l1Bal)} ETH; depositing ${ethers.formatEther(amount)} ETH ...`);

  const tx = await wallet.deposit({ token: utils.ETH_ADDRESS, amount, to: wallet.address });
  console.log(`L1 deposit tx: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`L1 deposit confirmed in block ${receipt.blockNumber}; waiting for L2 credit ...`);

  // Poll L2 balance until the deposit is processed (priority ops take a few minutes).
  const deadline = Date.now() + 20 * 60 * 1000;
  while (Date.now() < deadline) {
    const bal = await l2.getBalance(wallet.address);
    if (bal > before) {
      console.log(`L2 balance now ${ethers.formatEther(bal)} ETH.`);
      return;
    }
    await new Promise((r) => setTimeout(r, 15000));
    process.stdout.write(".");
  }
  throw new Error("Timed out waiting for L2 deposit to be credited");
}

function req(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env ${name}`);
  return v;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
