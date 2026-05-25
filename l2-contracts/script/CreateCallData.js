/**
 * callDataGenerator.ts
 *
 * Generates ABI-encoded call data for any function and arguments.
 *
 * INSTRUCTIONS:
 * 1. Edit the `functionSignatures` array to include the function signature for each call (e.g., "mint(address,uint256)", "transfer(address,uint256)").
 * 2. Edit the `argsList` array to include the arguments for each call, in the same order as the function signatures.
 * 3. Run with: npx ts-node callDataGenerator.ts
 * 4. The script will print the ABI-encoded call data for each function/argument pair.
 */

import { ethers } from "ethers";

// === CONFIGURATION ===

/**
 * List of function signatures for each call.
 * Example: ["mint(address,uint256)", "transfer(address,uint256)", ...]
 */
const functionSignatures = [
  "mint(address,uint256)",
  "transfer(address,uint256)",
  "transfer(address,uint256)",
  // ...add more as needed
];

/**
 * List of argument arrays for each call.
 * Each entry should match the corresponding function signature.
 */
  const argsList = [
  // For mint(address,uint256)
  ["0xA00F1d7c90BaA48650a79859C0950016469F01B1", ethers.parseUnits("10", 18)],
  // For transfer(address,uint256)
  ["0x7A860e9c0986B5F7B1aB6AE7f0017d793dFcEa2E", ethers.parseUnits("1", 18)],
  ["0x5144EDF6a2E7677433BBbD04618702c1c9DF3C25", ethers.parseUnits("1", 18)],
  // ...add more as needed
];

// === GENERATE CALLDATAS ===

const callDatas = functionSignatures.map((sig, i) => {
  const iface = new ethers.Interface([`function ${sig}`]);
  // Get function name (before first parenthesis)
  const funcName = sig.split("(")[0];
  return iface.encodeFunctionData(funcName, argsList[i]);
});

// === OUTPUT ===

console.log("callDatas:");
callDatas.forEach((cd, i) => {
  console.log(`${i + 1}: ${cd}`);
});
