import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
//
// The ADMIN_ACCOUNT is the account that will be able set minter/burner roles for other accounts.
// For local testing purposes, the ADMIN_ACCOUNT is set to local hardhat account 1.
const ADMIN_ACCOUNT = "0x478A1eBE665396ce0F2F87aB0F057aC273451B92";
const INITIAL_MINT_ACCOUNT = "0x478A1eBE665396ce0F2F87aB0F057aC273451B92";
const INITIAL_MINT_AMOUNT = 0;

// The SALT_IMPL and SALT_PROXY values are used to derive the contract addresses and are set to arbitrary values for local testing.
const SALT_IMPL = "0x8ceb348f712ba12ccf22e8a2228a74a6f75ea1d2ca4afe04ed7aa430528e4b99";
const SALT_PROXY = "0x8ceb348f712ba12ccf22e8a2228a74a6f75ea1d2ca4afe04ed7aa430528e4b99";

async function main() {
  dotEnvConfig();

  // For local testing purposes, the deployer private key is (via environment variable) is set to the private key of the local hardhat account 0.
  // For actual deploys, the deployer private key environment variable should be set to the private key of the account executing this deploy script.
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkTokenV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet, 'create2');

  const contract = await deployer.loadArtifact(contractName);
  const zkTokenV1 = await hre.zkUpgrades.deployProxy(
    deployer.zkWallet,
    contract,
    [ADMIN_ACCOUNT, INITIAL_MINT_ACCOUNT, INITIAL_MINT_AMOUNT],
    {
      initializer: "initialize",
      saltImpl: SALT_IMPL,
      deploymentTypeImpl: "create2",
      saltProxy: SALT_PROXY,
      deploymentTypeProxy: "create2"
    });

  await zkTokenV1.waitForDeployment();
  console.log(contractName + " deployed to:", await zkTokenV1.getAddress());

  zkTokenV1.connect(zkWallet);
  const totalSupply = await zkTokenV1.totalSupply();
  console.log("ZkTokenV1 totalSupply: ", totalSupply);

  const minterBalance = await zkTokenV1.balanceOf(INITIAL_MINT_ACCOUNT);
  console.log(`Balance of ${INITIAL_MINT_ACCOUNT}: ${minterBalance}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
