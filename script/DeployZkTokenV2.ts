import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

async function main() {
  dotEnvConfig();

  // For local testing purposes, the deployer private key is (via environment variable) is set to the private key of the local hardhat account 0.
  // For actual deploys, the deployer private key environment variable should be set to the private key of the account executing this deploy script.
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkTokenV2";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const zkTokenV2 = await deployer.deploy(contract, []);

  await zkTokenV2.waitForDeployment();
  console.log(contractName + " deployed to:", await zkTokenV2.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
