import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const SIGNER_ACCOUNT = "0x478A1eBE665396ce0F2F87aB0F057aC273451B92";
const OWNER_ACCOUNT = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045";

async function main() {
  dotEnvConfig();

  // For local testing purposes, the deployer private key is (via environment variable) is set to the private key of the local hardhat account 0.
  // For actual deploys, the deployer private key environment variable should be set to the private key of the account executing this deploy script.
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "SignatureBasedPaymaster";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  const signatureBasedPaymaster = await deployer.deploy(
    contract,
    [SIGNER_ACCOUNT]
  );

  await signatureBasedPaymaster.waitForDeployment();
  console.log(contractName + " deployed to:", await signatureBasedPaymaster.getAddress());

  const owner = await signatureBasedPaymaster.owner();
  console.log("SignatureBasedPaymaster initial owner: ", owner);

  console.log("Change ownership...");

  const tx = await signatureBasedPaymaster.transferOwnership(OWNER_ACCOUNT);
  await tx.wait();

  const newOwner = await signatureBasedPaymaster.owner();
  const signer = await signatureBasedPaymaster.signer();
  console.log("SignatureBasedPaymaster new owner: ", newOwner);
  console.log("SignatureBasedPaymaster signer: ", signer);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
