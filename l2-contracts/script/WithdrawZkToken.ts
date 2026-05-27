/**
 * WithdrawZkToken.ts
 *
 * Supports two commands for bridging ZK tokens from ZKsync Era back to L1:
 *
 *   withdraw  – Initiates a withdrawal on L2. Burns the ZK token on L2 and emits
 *               a bridge message to L1.  Prints the L2 transaction hash needed for
 *               the finalise step.
 *
 *   finalize  – Finalises a previously-initiated withdrawal on L1.  Must be called
 *               after the ZKsync proof window (~24 h on mainnet, shorter on testnet).
 *               Requires both an L2 wallet (to look up the proof) and an L1 wallet.
 *
 * Usage:
 *   # Initiate withdrawal from L2
 *   COMMAND=withdraw \
 *   L2_WALLET_PRIVATE_KEY=0x... \
 *   ZK_TOKEN_ADDRESS=0x... \
 *   WITHDRAW_AMOUNT=100 \
 *   L1_RECEIVER=0x... \
 *     npx hardhat run script/WithdrawZkToken.ts --network zkSyncTestnet
 *
 *   # Finalise withdrawal on L1
 *   COMMAND=finalize \
 *   L2_WALLET_PRIVATE_KEY=0x... \
 *   L1_WALLET_PRIVATE_KEY=0x... \
 *   WITHDRAWAL_TX_HASH=0x... \
 *     npx hardhat run script/WithdrawZkToken.ts --network zkSyncTestnet
 *
 * Required env vars per command:
 *
 *   Both commands:
 *     COMMAND                – "withdraw" | "finalize"
 *     L2_WALLET_PRIVATE_KEY  – private key of the L2 wallet initiating / monitoring
 *
 *   withdraw only:
 *     ZK_TOKEN_ADDRESS       – address of the ZK token proxy on L2
 *     WITHDRAW_AMOUNT        – human-readable amount of ZK to withdraw (e.g. "100")
 *     L1_RECEIVER            – L1 address that will receive the tokens (defaults to L2 wallet address)
 *
 *   finalize only:
 *     L1_WALLET_PRIVATE_KEY  – private key of the L1 wallet paying for finalisation gas
 *     WITHDRAWAL_TX_HASH     – L2 transaction hash returned by the withdraw command
 *     WITHDRAWAL_INDEX       – (optional) log index, defaults to 0
 *
 * Networks are read from Hardhat config.  When running against zkSyncTestnet the
 * L1 network is Sepolia; when running against zkSyncEra the L1 network is mainnet.
 */

import { config as dotEnvConfig } from "dotenv";
import { Provider, Wallet } from "zksync-ethers";
import { ethers } from "ethers";

dotEnvConfig();

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/**
 * L2NativeTokenVault – predeploy address on every ZKsync Era chain.
 * When withdrawing an L2-native ERC20 token, the NTV calls transferFrom() to
 * pull the tokens from the sender, so an approval is required before withdrawal.
 */
const L2_NATIVE_TOKEN_VAULT = "0x0000000000000000000000000000000000010004";

// ---------------------------------------------------------------------------
// Minimal ERC-20 ABI (approve + balanceOf only)
// ---------------------------------------------------------------------------
const ERC20_ABI = [
  "function balanceOf(address account) external view returns (uint256)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) external view returns (uint256)",
  "function decimals() external view returns (uint8)",
  "function symbol() external view returns (string)",
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

/** Return an L1 JSON-RPC URL.  Set L1_RPC in your environment. */
function getL1RpcUrl(): string {
  const url = process.env.L1_RPC;
  if (!url) throw new Error("Please set L1_RPC to the L1 (Ethereum) JSON-RPC endpoint");
  return url;
}

/** Return an L2 JSON-RPC URL.  Set L2_RPC in your environment. */
function getL2RpcUrl(): string {
  const url = process.env.L2_RPC;
  if (!url) throw new Error("Please set L2_RPC to the ZKsync Era JSON-RPC endpoint");
  return url;
}

// ---------------------------------------------------------------------------
// Command: withdraw
// ---------------------------------------------------------------------------

async function runWithdraw() {
  const l2PrivateKey   = requireEnv("L2_WALLET_PRIVATE_KEY");
  const zkTokenAddress = requireEnv("ZK_TOKEN_ADDRESS");
  const withdrawAmount = requireEnv("WITHDRAW_AMOUNT");
  const l1Receiver     = process.env.L1_RECEIVER; // optional, defaults to L2 wallet addr

  const l2Provider = new Provider(getL2RpcUrl());
  const l1Provider = new ethers.JsonRpcProvider(getL1RpcUrl());
  const wallet = new Wallet(l2PrivateKey, l2Provider, l1Provider);
  const walletAddress = await wallet.getAddress();

  const token = new ethers.Contract(zkTokenAddress, ERC20_ABI, wallet);
  const decimals = await token.decimals();
  const symbol   = await token.symbol();
  const amount   = ethers.parseUnits(withdrawAmount, decimals);

  console.log("\n=== ZK Token Withdrawal ===");
  console.log(`Token    : ${zkTokenAddress} (${symbol})`);
  console.log(`Amount   : ${withdrawAmount} ${symbol}`);
  console.log(`From (L2): ${walletAddress}`);
  console.log(`To   (L1): ${l1Receiver ?? walletAddress}`);

  // Check L2 balance
  const balance = await token.balanceOf(walletAddress);
  if (balance < amount) {
    throw new Error(
      `Insufficient balance: have ${ethers.formatUnits(balance, decimals)} ${symbol}, need ${withdrawAmount}`
    );
  }
  console.log(`L2 balance: ${ethers.formatUnits(balance, decimals)} ${symbol}`);

  // For L2-native ERC20 tokens the L2NativeTokenVault calls transferFrom() to
  // pull the tokens before burning them.  We therefore need to approve the NTV
  // before submitting the withdrawal.
  const token2 = new ethers.Contract(zkTokenAddress, ERC20_ABI, wallet);
  const currentAllowance = await token2.allowance(walletAddress, L2_NATIVE_TOKEN_VAULT);
  if (currentAllowance < amount) {
    console.log(`\nApproving L2NativeTokenVault (${L2_NATIVE_TOKEN_VAULT}) to spend ${withdrawAmount} ${symbol}…`);
    const approveTx = await token2.approve(L2_NATIVE_TOKEN_VAULT, amount);
    await approveTx.wait();
    console.log("  Approval confirmed.");
  } else {
    console.log("\nL2NativeTokenVault already has sufficient allowance.");
  }

  // Initiate withdrawal using the zksync-ethers Wallet helper.
  // Internally this calls L2AssetRouter.withdraw(assetId, assetData).
  console.log("\nInitiating withdrawal transaction on L2…");
  const withdrawTx = await wallet.withdraw({
    token: zkTokenAddress,
    amount,
    to: l1Receiver ?? walletAddress,
  });

  console.log(`L2 tx hash: ${withdrawTx.hash}`);
  console.log("Waiting for L2 transaction to be mined…");
  const receipt = await withdrawTx.wait();
  console.log(`L2 tx mined in block ${receipt?.blockNumber}`);

  console.log("\n✅ Withdrawal initiated successfully.");
  console.log(`\nSave the following transaction hash for the finalize step:`);
  console.log(`  WITHDRAWAL_TX_HASH=${withdrawTx.hash}`);
  console.log("\nNote: the withdrawal can be finalised on L1 only after the proof window");
  console.log("      (~24 h on mainnet, ~1 h on Sepolia testnet).");
  console.log("\nRun finalize command:");
  console.log(
    `  COMMAND=finalize L2_WALLET_PRIVATE_KEY=<key> L1_WALLET_PRIVATE_KEY=<key> WITHDRAWAL_TX_HASH=${withdrawTx.hash} \\`
  );
  console.log(`    npx hardhat run script/WithdrawZkToken.ts --network ${process.env.HARDHAT_NETWORK ?? "zkSyncTestnet"}`);
}

// ---------------------------------------------------------------------------
// Command: finalize
// ---------------------------------------------------------------------------

async function runFinalize() {
  const l2PrivateKey   = requireEnv("L2_WALLET_PRIVATE_KEY");
  const l1PrivateKey   = requireEnv("L1_WALLET_PRIVATE_KEY");
  const withdrawalHash = requireEnv("WITHDRAWAL_TX_HASH");
  const withdrawalIndex = parseInt(process.env.WITHDRAWAL_INDEX ?? "0", 10);

  const l2Provider = new Provider(getL2RpcUrl());
  const l1Provider = new ethers.JsonRpcProvider(getL1RpcUrl());

  // l2Wallet is used to fetch proof data (read-only L2 calls)
  const l2Wallet = new Wallet(l2PrivateKey, l2Provider, l1Provider);
  // l1Wallet signs and pays for the L1 finalise transaction
  const l1Wallet = new Wallet(l1PrivateKey, l2Provider, l1Provider);

  console.log("\n=== ZK Token Withdrawal Finalisation ===");
  console.log(`L2 withdrawal tx : ${withdrawalHash}`);
  console.log(`Index            : ${withdrawalIndex}`);
  console.log(`L1 sender (gas)  : ${await l1Wallet.getAddress()}`);

  // Check whether already finalised.
  // Note: isWithdrawalFinalized may throw if the proof is not yet available,
  // which means the batch has not been committed / proven on L1 yet.
  let alreadyFinalised = false;
  try {
    alreadyFinalised = await l2Wallet.isWithdrawalFinalized(withdrawalHash, withdrawalIndex);
  } catch (e: any) {
    const msg: string = e?.message ?? String(e);
    if (msg.includes("Log proof not found") || msg.includes("proof not found")) {
      console.log(
        "\n⏳ Withdrawal proof is not yet available on L1.\n" +
          "   The ZKsync sequencer must include this withdrawal in a batch and have it proved on L1\n" +
          "   before finalisation is possible. On Sepolia testnet this typically takes ~1 hour.\n" +
          "   Re-run this command after the proof window has passed."
      );
      return;
    }
    throw e;
  }

  if (alreadyFinalised) {
    console.log("\n✅ Withdrawal is already finalised on L1. Nothing to do.");
    return;
  }

  console.log("\nFinalising withdrawal on L1…");
  const finaliseTx = await l1Wallet.finalizeWithdrawal(withdrawalHash, withdrawalIndex);
  console.log(`L1 tx hash: ${finaliseTx.hash}`);
  console.log("Waiting for L1 transaction to be mined…");
  const receipt = await finaliseTx.wait();
  console.log(`L1 tx mined in block ${receipt?.blockNumber}`);

  console.log("\n✅ Withdrawal finalised successfully.");
  console.log("   The ZK tokens are now available on L1.");
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main() {
  const command = requireEnv("COMMAND");

  switch (command.toLowerCase()) {
    case "withdraw":
      await runWithdraw();
      break;
    case "finalize":
      await runFinalize();
      break;
    default:
      throw new Error(`Unknown command: "${command}". Use "withdraw" or "finalize".`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
