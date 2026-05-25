/**
 * createDripCallData.js
 *
 * Generates ABI-encoded call data for sending tokens to a Drips Drip List.
 *
 * INSTRUCTIONS:
 * 1. Set your Drip List address (from Drips UI) in the `dripListAddress` variable
 * 2. Set the amount you want to send to the Drip List in the `amount` variable
 * 3. Run with: node createDripCallData.js
 * 4. The script will print the ABI-encoded call data for the transfer
 * 5. Use this callData in your ZkMinterModTriggerV1 contract
 *
 * WORKFLOW:
 * 1. Create a Drip List on Drips UI (https://drips.network)
 * 2. Add your recipients and set their percentages
 * 3. Copy the Drip List address
 * 4. Run this script to generate the callData
 * 5. Deploy your trigger contract with this callData
 * 6. When mint() is called, tokens will be sent to Drips for automatic distribution
 */

import { ethers } from "ethers";

// === CONFIGURATION ===

/**
 * The Drip List address from Drips UI
 * Replace with your actual Drip List address
 */
const dripListAddress = "0x1234567890123456789012345678901234567890";

/**
 * Amount to send to the Drip List (in tokens)
 * This will be automatically split among your recipients
 */
const amount = ethers.parseUnits("1.0", 18); // 1 token with 18 decimals

// === GENERATE CALLDATA ===

/**
 * Function signature for ERC20 transfer
 */
const functionSignature = "transfer(address,uint256)";

/**
 * Arguments for the transfer function
 * [recipient, amount]
 */
const args = [dripListAddress, amount];

// Create interface and encode function data
const iface = new ethers.Interface([`function ${functionSignature}`]);
const callData = iface.encodeFunctionData("transfer", args);

// === OUTPUT ===

console.log("=== DRIPS INTEGRATION CALLDATA ===");
console.log("");
console.log("Drip List Address:", dripListAddress);
console.log("Amount:", ethers.formatUnits(amount, 18), "tokens");
console.log("");
console.log("Function Signature:", functionSignature);
console.log("Call Data:", callData);
console.log("");
console.log("=== DEPLOYMENT CONFIG ===");
console.log("");
console.log("For your ZkMinterModTriggerV1 contract:");
console.log("targets[0]: [YOUR_TOKEN_CONTRACT_ADDRESS]");
console.log("functionSignatures[0]: 0xa9059cbb");
console.log("callDatas[0]:", callData);
console.log("");
console.log("=== HOW IT WORKS ===");
console.log("1. Your contract mints tokens to itself");
console.log("2. Your contract calls: token.transfer(dripListAddress, amount)");
console.log("3. Drips automatically distributes tokens to your recipients monthly");
console.log("4. Recipients can claim their funds from Drips");
