import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const ADMIN_ACCOUNT = "0xdEADBEeF00000000000000000000000000000000";
const TOKEN_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
const MERKLE_ROOT = "0x0000000000000000000000000000000000000000000000000000000000000001";
const MAX_CLAIMABLE = "1000000000000000000000000000"; // raw decimals, bigint fails to encode with deploy
const WINDOW_START = 1750000000
const WINDOW_END = 1760000000

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMerkleDistributor";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [ADMIN_ACCOUNT, TOKEN_ADDRESS, MERKLE_ROOT, MAX_CLAIMABLE, WINDOW_START, WINDOW_END];
  const distributor = await deployer.deploy(contract, constructorArgs);

  console.log("constructor args:" + distributor.interface.encodeDeploy(constructorArgs));

  const contractAddress = await distributor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const root = await distributor.MERKLE_ROOT();
  console.log(`The merkle root is ${root}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
