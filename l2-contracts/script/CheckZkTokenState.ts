/**
 * CheckZkTokenState.ts
 *
 * Verifies the state of a deployed ZkTokenV2 proxy.
 *
 * Usage:
 *   ZK_TOKEN_PROXY=0x... npx hardhat run script/CheckZkTokenState.ts --network stageProofs
 */

import { config as dotEnvConfig } from "dotenv";
import { Provider } from "zksync-ethers";
import { ethers } from "ethers";
import * as hre from "hardhat";
import * as path from "path";
import * as fs from "fs";

dotEnvConfig();

// EIP-1967 storage slots
const IMPL_SLOT  = "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
const ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";

const TOKEN_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function DEFAULT_ADMIN_ROLE() view returns (bytes32)",
  "function MINTER_ADMIN_ROLE() view returns (bytes32)",
  "function BURNER_ADMIN_ROLE() view returns (bytes32)",
  "function MINTER_ROLE() view returns (bytes32)",
  "function BURNER_ROLE() view returns (bytes32)",
  "function hasRole(bytes32 role, address account) view returns (bool)",
];

const PROXY_ADMIN_ABI = [
  "function owner() view returns (address)",
  "function getProxyAdmin(address proxy) view returns (address)",
  "function getProxyImplementation(address proxy) view returns (address)",
];

function slotToAddress(slot: string): string {
  return ethers.getAddress("0x" + slot.slice(-40));
}

/** keccak256 of the deployed bytecode, used as a fingerprint. */
function codeHash(bytecode: string): string {
  return ethers.keccak256(bytecode);
}

/** Load the deployedBytecode from a zk artifact (artifacts-zk directory). */
function loadArtifactBytecode(contractName: string): string {
  // Search artifacts-zk recursively for <ContractName>.json
  const base = path.join(__dirname, "..", "artifacts-zk");
  const found = findFile(base, `${contractName}.json`);
  if (!found) throw new Error(`Artifact not found for ${contractName}`);
  const artifact = JSON.parse(fs.readFileSync(found, "utf-8"));
  const deployed = artifact.deployedBytecode ?? artifact.bytecode;
  if (!deployed) throw new Error(`No bytecode in artifact for ${contractName}`);
  return deployed;
}

function findFile(dir: string, name: string): string | null {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      const result = findFile(full, name);
      if (result) return result;
    } else if (entry.name === name && !entry.name.endsWith(".dbg.json")) {
      return full;
    }
  }
  return null;
}

function checkCode(label: string, deployed: string, expectedBytecode: string): boolean {
  if (deployed === "0x") {
    console.log(`  ❌ ${label}: no code deployed`);
    return false;
  }
  const deployedHash  = codeHash(deployed);
  const expectedHash  = codeHash(expectedBytecode);
  const match = deployedHash === expectedHash;
  console.log(`  ${match ? "✅" : "❌"} ${label}: bytecode hash ${match ? "matches artifact" : "MISMATCH"}`);
  if (!match) {
    console.log(`       deployed : ${deployedHash}`);
    console.log(`       expected : ${expectedHash}`);
  }
  return match;
}

async function main() {
  dotEnvConfig();

  const proxyAddress = process.env.ZK_TOKEN_PROXY;
  if (!proxyAddress) throw new Error("Set ZK_TOKEN_PROXY env var");

  const l2RpcUrl = process.env.L2_RPC;
  if (!l2RpcUrl) throw new Error("Set L2_RPC env var");

  const provider = new Provider(l2RpcUrl);

  console.log("=".repeat(60));
  console.log("ZkToken State Check");
  console.log("=".repeat(60));
  console.log(`Proxy : ${proxyAddress}\n`);

  // ------------------------------------------------------------------
  // 1. Read EIP-1967 slots for implementation and admin
  // ------------------------------------------------------------------
  const [implSlotVal, adminSlotVal] = await Promise.all([
    provider.getStorage(proxyAddress, IMPL_SLOT),
    provider.getStorage(proxyAddress, ADMIN_SLOT),
  ]);

  const implAddress       = slotToAddress(implSlotVal);
  const proxyAdminAddress = slotToAddress(adminSlotVal);

  console.log("--- Proxy internals (EIP-1967) ---");
  console.log(`Implementation : ${implAddress}`);
  console.log(`ProxyAdmin     : ${proxyAdminAddress}`);

  // Confirm both have code
  const [implCode, adminCode, proxyCode] = await Promise.all([
    provider.getCode(implAddress),
    provider.getCode(proxyAdminAddress),
    provider.getCode(proxyAddress),
  ]);

  console.log("Bytecode verification:");
  const implOk  = checkCode("Implementation (ZkTokenV2)", implCode,  loadArtifactBytecode("ZkTokenV2"));
  const adminOk = checkCode("ProxyAdmin",                 adminCode, loadArtifactBytecode("ProxyAdmin"));
  const proxyOk = checkCode("Proxy (TransparentUpgradeableProxy)", proxyCode, loadArtifactBytecode("TransparentUpgradeableProxy"));

  // ------------------------------------------------------------------
  // 2. Check _initialized == 2  (slot 0, byte 0 of the proxy storage)
  //    Initializable packs _initialized (uint8) into slot 0 offset 0
  // ------------------------------------------------------------------
  const slot0 = await provider.getStorage(proxyAddress, "0x0");
  const initialized = parseInt(slot0.slice(-2), 16); // lowest byte

  console.log("\n--- Initializer ---");
  console.log(`_initialized   : ${initialized} ${initialized === 2 ? "✅ (initializeV2 called)" : "⚠️  expected 2"}`);

  // ------------------------------------------------------------------
  // 3. Basic token info
  // ------------------------------------------------------------------
  const token = new ethers.Contract(proxyAddress, TOKEN_ABI, provider);
  const [name, symbol, decimals, totalSupply] = await Promise.all([
    token.name(),
    token.symbol(),
    token.decimals(),
    token.totalSupply(),
  ]);

  console.log("\n--- Token info ---");
  console.log(`Name           : ${name}`);
  console.log(`Symbol         : ${symbol}`);
  console.log(`Decimals       : ${decimals}`);
  console.log(`Total supply   : ${ethers.formatUnits(totalSupply, decimals)} ${symbol}`);

  // ------------------------------------------------------------------
  // 4. ProxyAdmin owner and their roles
  // ------------------------------------------------------------------
  const proxyAdmin = new ethers.Contract(proxyAdminAddress, PROXY_ADMIN_ABI, provider);
  const proxyOwner = await proxyAdmin.owner();

  const [DEFAULT_ADMIN, MINTER_ADMIN, BURNER_ADMIN, MINTER, BURNER] = await Promise.all([
    token.DEFAULT_ADMIN_ROLE(),
    token.MINTER_ADMIN_ROLE(),
    token.BURNER_ADMIN_ROLE(),
    token.MINTER_ROLE(),
    token.BURNER_ROLE(),
  ]);

  const roles = [
    { name: "DEFAULT_ADMIN_ROLE", id: DEFAULT_ADMIN },
    { name: "MINTER_ADMIN_ROLE",  id: MINTER_ADMIN },
    { name: "BURNER_ADMIN_ROLE",  id: BURNER_ADMIN },
    { name: "MINTER_ROLE",        id: MINTER },
    { name: "BURNER_ROLE",        id: BURNER },
  ];

  const hasRoles = await Promise.all(roles.map(r => token.hasRole(r.id, proxyOwner)));

  console.log("\n--- ProxyAdmin owner ---");
  console.log(`Owner          : ${proxyOwner}`);
  console.log("Roles:");
  roles.forEach((r, i) => {
    console.log(`  ${hasRoles[i] ? "✅" : "❌"} ${r.name}`);
  });

  // ------------------------------------------------------------------
  // Summary
  // ------------------------------------------------------------------
  const allRoles = hasRoles.every(Boolean);
  const ok = implOk && adminOk && proxyOk && initialized === 2 && allRoles;
  console.log("\n" + "=".repeat(60));
  console.log(ok ? "✅  All checks passed." : "⚠️  Some checks failed – see above.");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
