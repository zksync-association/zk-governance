import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const TOKEN_ADDRESS = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const ADMIN_ACCOUNT = "0x1054cB76FF7d77C387c82d1E0aFC374fD0cA86d9";
const CAP_AMOUNT = "3489000000000000000000000000"; // raw decimals, bigint fails to encode with deploy :shrug:
const SALT = "0x8ceb348f712ba12ccf22e8a2228a74a6f75ea1d2ca4afe04ed7aa430528e4b99";

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkCappedMinter";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet, 'create2');

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [TOKEN_ADDRESS, ADMIN_ACCOUNT, CAP_AMOUNT];
  const customData = {salt: SALT};
  const cappedMinter = await deployer.deploy(contract, constructorArgs, {customData});

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
