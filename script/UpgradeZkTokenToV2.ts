import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet, Contract } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real upgrade, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of upgrade can be checked in along with the deployment artifacts
// produced by running the scripts.
const ZK_TOKEN_PROXY = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";

async function main() {
  dotEnvConfig();

  // For local testing purposes, the deployer private key is (via environment variable) is set to the private key of the local hardhat account 0.
  // For actual deploys, the deployer private key environment variable should be set to the private key of the account executing this deploy script.
  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkTokenV2";
  console.log("Upgrading token to  '" + contractName + "' version...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const contract = await deployer.loadArtifact(contractName);
  await hre.zkUpgrades.upgradeProxy(
    deployer.zkWallet,
    ZK_TOKEN_PROXY,
    contract,
    {call: "initializeV2"}
   );

  const zkTokenV2 = new Contract(ZK_TOKEN_PROXY, contract.abi, deployer.zkWallet);

  const name = await zkTokenV2.name();
  console.log("ZkTokenV2 name: ", name);

  const symbol = await zkTokenV2.symbol();
  console.log("ZkTokenV2 symbol: ", symbol);

  const totalSupply = await zkTokenV2.totalSupply();
  console.log("ZkTokenV2 totalSupply: ", totalSupply);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
