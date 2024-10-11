import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";
import * as fs from 'fs';
import * as path from 'path';

// Get the bytecode hash from ZkCappedMinter.json in ./artifacts-zk
// Verify this bytecode hash before deploying as it can change if the the compilation of the capped minter changes
const BYTECODE_HASH = "0x010000796655576a236368c33802b0114af403108c937e84b2afa535371ee55c";

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkCappedMinterFactory";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet, 'create2');

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [BYTECODE_HASH];
  const factory = await deployer.deploy(contract, constructorArgs);

  console.log("constructor args: " + factory.interface.encodeDeploy(constructorArgs));

  const contractAddress = await factory.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const bytecodeHash = await factory.BYTECODE_HASH();
  console.log(`The BYTECODE_HASH is set to: ${bytecodeHash}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
