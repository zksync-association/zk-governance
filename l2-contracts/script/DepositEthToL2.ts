/**
 * DepositEthToL2.ts
 *
 * Bridges ETH from L1 to the same wallet address on L2 via the ZKsync bridge.
 *
 * Usage:
 *   PRIVATE_KEY=0x...   \
 *   DEPOSIT_AMOUNT=0.01 \
 *   L1_RPC=<l1-rpc-url> \
 *   L2_RPC=<l2-rpc-url> \
 *     npx hardhat run script/DepositEthToL2.ts --network <network>
 *
 * Required env vars:
 *   PRIVATE_KEY      – private key of the wallet (used on both L1 and L2)
 *   DEPOSIT_AMOUNT   – ETH amount to bridge (human-readable, e.g. "0.01")
 *   L1_RPC           – L1 Ethereum JSON-RPC endpoint
 *   L2_RPC           – ZKsync Era JSON-RPC endpoint
 */

import { config as dotEnvConfig } from "dotenv";
import { Provider, Wallet, utils } from "zksync-ethers";
import { ethers } from "ethers";

dotEnvConfig();

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

async function main() {
  const privateKey     = requireEnv("PRIVATE_KEY");
  const depositAmountRaw = requireEnv("DEPOSIT_AMOUNT");
  const l1RpcUrl       = requireEnv("L1_RPC");
  const l2RpcUrl       = requireEnv("L2_RPC");

  const l1Provider = new ethers.JsonRpcProvider(l1RpcUrl);
  const l2Provider = new Provider(l2RpcUrl);
  const wallet     = new Wallet(privateKey, l2Provider, l1Provider);
  const address    = await wallet.getAddress();

  const depositAmount = ethers.parseEther(depositAmountRaw);

  console.log("=".repeat(60));
  console.log("ETH L1 → L2 Deposit");
  console.log("=".repeat(60));
  console.log(`Wallet         : ${address}`);
  console.log(`Amount         : ${depositAmountRaw} ETH`);

  const l1Balance = await l1Provider.getBalance(address);
  const l2Balance = await l2Provider.getBalance(address);
  console.log(`L1 balance     : ${ethers.formatEther(l1Balance)} ETH`);
  console.log(`L2 balance     : ${ethers.formatEther(l2Balance)} ETH`);

  if (l1Balance < depositAmount) {
    throw new Error(
      `Insufficient L1 balance: have ${ethers.formatEther(l1Balance)} ETH, need ${depositAmountRaw} ETH`
    );
  }

  console.log("\nSubmitting deposit to L1 bridge…");
  const depositTx = await wallet.deposit({
    token: utils.ETH_ADDRESS,
    amount: depositAmount,
    to: address,
  });
  console.log(`L1 tx hash     : ${depositTx.hash}`);
  await depositTx.wait();
  console.log("L1 confirmed.");

  console.log("Waiting for L2 credit…");
  await depositTx.waitFinalize();
  console.log("L2 confirmed.");

  const l2BalanceAfter = await l2Provider.getBalance(address);
  console.log(`\nL2 balance after : ${ethers.formatEther(l2BalanceAfter)} ETH`);
  console.log("✅ Deposit complete.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
