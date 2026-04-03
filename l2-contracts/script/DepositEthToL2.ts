/**
 * DepositEthToL2.ts
 *
 * Bridges ETH from L1 to the same wallet address on L2 via the ZKsync bridge.
 *
 * Uses Bridgehub.requestL2TransactionDirect which is the correct universal path
 * for ETH (base token) deposits to any ZKsync chain. The legacy ZKChain diamond
 * requestL2Transaction is Era-only and returns OnlyEraSupported for other chains.
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
 *
 * Note: populateTransaction issues several sequential L1 RPC calls (nonce, gas
 * estimate, base cost, send). Rate-limited endpoints (e.g. Tenderly public
 * gateway) may cause it to fail. Use a non-rate-limited endpoint for L1_RPC,
 * e.g. https://ethereum-sepolia-rpc.publicnode.com for Sepolia.
 */

import { config as dotEnvConfig } from "dotenv";
import { Provider, Wallet, utils } from "zksync-ethers";
import { ethers } from "ethers";

dotEnvConfig();

// Re-export utilities that are used internally by the SDK but not re-exported.
const sdkUtils = require("zksync-ethers/build/utils");

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

async function main() {
  const privateKey       = requireEnv("PRIVATE_KEY");
  const depositAmountRaw = requireEnv("DEPOSIT_AMOUNT");
  const l1RpcUrl         = requireEnv("L1_RPC");
  const l2RpcUrl         = requireEnv("L2_RPC");

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

  // ------------------------------------------------------------------
  // Build the deposit via Bridgehub.requestL2TransactionDirect.
  //
  // The legacy ZKChain diamond requestL2Transaction() is Era-only and
  // reverts with OnlyEraSupported for other chains. The Bridgehub's
  // requestL2TransactionDirect is chain-agnostic.
  //
  // For ETH-based chains: mintValue = baseCost + depositAmount
  //   msg.value == mintValue (all ETH goes to the ZKChain via the Bridgehub)
  //   l2Value   == depositAmount (ETH to credit to l2Contract on L2)
  // ------------------------------------------------------------------

  const chainId   = (await l2Provider.getNetwork()).chainId;
  const bridgehub = await wallet.getBridgehubContract();

  // Estimate L2 gas needed for a plain ETH transfer
  const gasPerPubdataByte: bigint = BigInt(sdkUtils.REQUIRED_L1_TO_L2_GAS_PER_PUBDATA_LIMIT);
  const l2GasLimit = await l2Provider.estimateL1ToL2Execute({
    contractAddress: address,
    calldata: "0x",
    l2Value: depositAmount,
  });

  const feeData        = await l1Provider.getFeeData();
  const gasPriceForEst = feeData.maxFeePerGas ?? feeData.gasPrice ?? ethers.parseUnits("1", "gwei");
  const baseCost: bigint = await bridgehub.l2TransactionBaseCost(
    chainId,
    gasPriceForEst,
    l2GasLimit,
    gasPerPubdataByte,
  );

  // mintValue = baseCost + deposit (scale baseCost by 1.25 for safety margin)
  const mintValue  = ((baseCost * 125n) / 100n) + depositAmount;

  console.log(`\nBridgehub      : ${await bridgehub.getAddress()}`);
  console.log(`Base cost      : ${ethers.formatEther(baseCost)} ETH`);
  console.log(`Mint value     : ${ethers.formatEther(mintValue)} ETH`);

  console.log("\nSubmitting deposit via Bridgehub.requestL2TransactionDirect…");

  const populatedTx = await bridgehub.requestL2TransactionDirect.populateTransaction(
    {
      chainId,
      mintValue,
      l2Contract: address,
      l2Value: depositAmount,
      l2Calldata: "0x",
      l2GasLimit,
      l2GasPerPubdataByteLimit: gasPerPubdataByte,
      factoryDeps: [],
      refundRecipient: address,
    },
    { value: mintValue },
  );

  const walletL1  = new ethers.Wallet(privateKey, l1Provider);
  const sentTx    = await walletL1.sendTransaction(populatedTx);
  console.log(`L1 tx hash     : ${sentTx.hash}`);

  // Wrap in PriorityOpResponse so we get .waitL1Commit() and .wait()
  const depositTx = await wallet.getPriorityOpResponse(sentTx);

  await depositTx.waitL1Commit();
  console.log("L1 confirmed.");

  // wait() waits for L2 block inclusion (~minutes).
  // waitFinalize() would wait for the full ZK proof cycle (~hours).
  console.log("Waiting for L2 inclusion…");
  await depositTx.wait();
  console.log("L2 confirmed.");

  const l2BalanceAfter = await l2Provider.getBalance(address);
  console.log(`\nL2 balance after : ${ethers.formatEther(l2BalanceAfter)} ETH`);
  console.log("✅ Deposit complete.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
