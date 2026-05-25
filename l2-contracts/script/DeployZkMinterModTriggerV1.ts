import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import { ethers } from "ethers";
import * as hre from "hardhat";

// Deployment configuration
// Update these values or load from environment variables for the target environment
const ADMIN_ACCOUNT = process.env.ADMIN_ACCOUNT || "0xdEADBEeF00000000000000000000000000000000";
const TOKEN_ADDRESS = process.env.TOKEN_ADDRESS || "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
const TARGET_ADDRESS = process.env.TARGET_ADDRESS || "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5"; // MerkleDropFactory address
const MERKLE_ROOT = process.env.MERKLE_ROOT || "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef";
const IPFS_HASH = process.env.IPFS_HASH || "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890";
const MINT_AMOUNT = process.env.MINT_AMOUNT ? parseInt(process.env.MINT_AMOUNT) : 1000;


// ABI fragments for function signatures
const TOKEN_ABI = ["function approve(address spender, uint256 amount)"];
const TARGET_ABI = ["function addMerkleTree(bytes32 merkleRoot, bytes32 ipfsHash, address token, uint256 amount)"];

// Encode function signatures and call data
const tokenIface = new ethers.Interface(TOKEN_ABI);
const targetIface = new ethers.Interface(TARGET_ABI);

const APPROVE_SIGNATURE = tokenIface.getSighash("approve");
const ADD_MERKLE_TREE_SIGNATURE = targetIface.getSighash("addMerkleTree");

const APPROVE_CALL_DATA = ethers.AbiCoder.defaultAbiCoder().encode(
  ["address", "uint256"],
  [TARGET_ADDRESS, MINT_AMOUNT]
);
const ADD_MERKLE_TREE_CALL_DATA = ethers.AbiCoder.defaultAbiCoder().encode(
  ["bytes32", "bytes32", "address", "uint256"],
  [MERKLE_ROOT, IPFS_HASH, TOKEN_ADDRESS, MINT_AMOUNT]
);

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterModTriggerV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);

  // Prepare constructor arguments
  const targetAddresses = [TOKEN_ADDRESS, TARGET_ADDRESS];
  const functionSignatures = [APPROVE_SIGNATURE, ADD_MERKLE_TREE_SIGNATURE];
  const callDatas = [APPROVE_CALL_DATA, ADD_MERKLE_TREE_CALL_DATA];

  const constructorArgs = [
    ADMIN_ACCOUNT,
    targetAddresses,
    functionSignatures,
    callDatas,
  ];

  const distributor = await deployer.deploy(contract, constructorArgs);

  console.log("constructor args:" + distributor.interface.encodeDeploy(constructorArgs));

  const contractAddress = await distributor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
