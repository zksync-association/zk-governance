/**
 * MintZkToken.ts
 *
 * Mints ZK tokens to a recipient address. The caller must hold MINTER_ROLE on
 * the token contract.
 *
 * Usage:
 *   OWNER_PRIVATE_KEY=0x...  \
 *   ZK_TOKEN_PROXY=0x...     \
 *   MINT_TO=0x...            \
 *   MINT_AMOUNT=1000         \
 *     npx hardhat run script/MintZkToken.ts --network stageProofs
 *
 * Required env vars:
 *   OWNER_PRIVATE_KEY  – private key of an account holding MINTER_ROLE
 *   ZK_TOKEN_PROXY     – address of the ZkTokenV2 proxy
 *   MINT_TO            – recipient address
 *   MINT_AMOUNT        – amount of ZK to mint (human-readable, e.g. "1000")
 *   L2_RPC             – ZKsync Era JSON-RPC endpoint
 */

import { config as dotEnvConfig } from "dotenv";
import { Provider, Wallet } from "zksync-ethers";
import { ethers } from "ethers";

dotEnvConfig();

const TOKEN_ABI = [
  "function mint(address _to, uint256 _amount) external",
  "function MINTER_ROLE() view returns (bytes32)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
];

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

async function main() {
  const ownerPrivateKey = requireEnv("OWNER_PRIVATE_KEY");
  const proxyAddress    = requireEnv("ZK_TOKEN_PROXY");
  const mintTo          = requireEnv("MINT_TO");
  const mintAmountRaw   = requireEnv("MINT_AMOUNT");
  const l2RpcUrl        = requireEnv("L2_RPC");

  const provider   = new Provider(l2RpcUrl);
  const wallet     = new Wallet(ownerPrivateKey, provider);
  const minter     = await wallet.getAddress();
  const token      = new ethers.Contract(proxyAddress, TOKEN_ABI, wallet);

  const decimals    = await token.decimals();
  const mintAmount  = ethers.parseUnits(mintAmountRaw, decimals);
  const MINTER_ROLE = await token.MINTER_ROLE();

  console.log("=".repeat(60));
  console.log("ZkToken Mint");
  console.log("=".repeat(60));
  console.log(`Token   : ${proxyAddress}`);
  console.log(`Minter  : ${minter}`);
  console.log(`To      : ${mintTo}`);
  console.log(`Amount  : ${mintAmountRaw} ZK`);

  // Pre-flight: confirm the caller has MINTER_ROLE
  const hasMinterRole = await token.hasRole(MINTER_ROLE, minter);
  if (!hasMinterRole) {
    throw new Error(`${minter} does not hold MINTER_ROLE on ${proxyAddress}`);
  }

  const balanceBefore = await token.balanceOf(mintTo);
  console.log(`\nRecipient balance before : ${ethers.formatUnits(balanceBefore, decimals)} ZK`);

  console.log("\nSending mint transaction…");
  const tx = await token.mint(mintTo, mintAmount);
  console.log(`Tx hash : ${tx.hash}`);
  await tx.wait();
  console.log("Confirmed.");

  const balanceAfter  = await token.balanceOf(mintTo);
  const totalSupply   = await token.totalSupply();
  console.log(`Recipient balance after  : ${ethers.formatUnits(balanceAfter, decimals)} ZK`);
  console.log(`Total supply             : ${ethers.formatUnits(totalSupply, decimals)} ZK`);
  console.log("\n✅ Mint complete.");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
