import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const TOKEN_ADDRESS = "0xCAFEcaFE00000000000000000000000000000000";
const ADMIN_ACCOUNT = "0xdEADBEeF00000000000000000000000000000000";
const CAP_AMOUNT = "1000000000000000000000000000"; // raw decimals, bigint fails to encode with deploy :shrug:

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkCappedMinter";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [TOKEN_ADDRESS, ADMIN_ACCOUNT, CAP_AMOUNT];
  const cappedMinter = await deployer.deploy(contract, constructorArgs);

  console.log("constructor args:" + cappedMinter.interface.encodeDeploy(constructorArgs));

  const contractAddress = await cappedMinter.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const capValue = await cappedMinter.CAP();
  console.log(`The Cap is set to: ${capValue}`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
