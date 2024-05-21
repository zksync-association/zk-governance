import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
//
// The NEW_OWNER is the account that will be the new proxy admin owner.
// For local testing purposes, the ADMIN_ACCOUNT is set to local hardhat account 3.
const NEW_OWNER = "0x3cFc0e11D88B38A7577DAB36f3a8E5e8538a8C22";

async function main() {
  dotEnvConfig();

  // For local testing purposes, the deployer private key is set (via environment variable) to the private key of the local hardhat account 0.
  // For actual deploys, the deployer private key environment variable should be set to the private key of the account executing this deploy script.
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkTokenV1";
  console.log("Transferring proxy admin owner for " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const adminInstance = await hre.zkUpgrades.admin.getInstance(deployer.zkWallet);
  const currentAdminInstanceOwner = await adminInstance.owner();

  if (currentAdminInstanceOwner === NEW_OWNER) {
    console.log("Current proxy admin instance owner is already set to " + NEW_OWNER);
    return;
  }
  console.log("Current proxy admin instance owner: " + currentAdminInstanceOwner);

  await hre.zkUpgrades.admin.transferProxyAdminOwnership(NEW_OWNER, deployer.zkWallet);
  
  const newAdminInstanceOwner = await adminInstance.owner();
  if (newAdminInstanceOwner === NEW_OWNER) {
    console.log("Successfully proxy admin instance owner to " + newAdminInstanceOwner);
  } else {
    throw `Failed to transfer proxy admin instance owner to ${NEW_OWNER}`;
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
