import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deploying
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const MINTABLE_ADDRESS = ""; // TODO: Update this to the actual mintable address.
const ADMIN_ACCOUNT = ""; // TODO: Update this to the actual admin account.
const MINT_RATE_LIMIT = "1000000000000000000000"; // TODO: Update this to the actual mint rate limit. Currently set to 1000 tokens.
const MINT_RATE_LIMIT_WINDOW = 86400; // TODO: Update this to the actual mint rate limit window. Currently set to 24 hours.
const SALT = ""; // TODO: Update this to the actual salt.

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const contractName = "ZkMinterRateLimiterV1";
  console.log("Deploying " + contractName + "...");

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet, "create2");

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [
    MINTABLE_ADDRESS,
    ADMIN_ACCOUNT,
    MINT_RATE_LIMIT,
    MINT_RATE_LIMIT_WINDOW,
  ];
  const customData = { salt: SALT };
  const rateLimiter = await deployer.deploy(contract, constructorArgs, {
    customData,
  });

  console.log(
    "constructor args:" + rateLimiter.interface.encodeDeploy(constructorArgs)
  );

  const contractAddress = await rateLimiter.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const mintRateLimit = await rateLimiter.mintRateLimit();
  console.log(`The mint rate limit is set to: ${mintRateLimit}`);

  const mintRateLimitWindow = await rateLimiter.mintRateLimitWindow();
  console.log(`The mint rate limit window is set to: ${mintRateLimitWindow}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
