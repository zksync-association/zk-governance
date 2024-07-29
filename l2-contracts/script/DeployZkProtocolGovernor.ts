import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const contractName = "ZkProtocolGovernor";
const tokenAddress = "0x69e5DC39E2bCb1C17053d2A4ee7CAEAAc5D36f96";  // TODO: We'll need to deploy this contract first to get the actual address
const votingDelay = 60 * 15; // For test purposes, 15 minutes
const votingPeriod = 60 * 15; // For test purposes, 15 minutes
const proposalThreshold = 10; // For testing purposes, actual deployment will need real values
const initialQuorum = 100; // For testing purposes, actual deployment will need real values
const initialLateQuorum = 60 * 15; // For test purposes, 15 minutes

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  // deploy timelock controller for the protocol governor
  console.log(`Deploying ${contractName} TimelockController contract...`);
  const timelockContract = await deployer.loadArtifact("TimelockController");
  const adminAddress = await zkWallet.getAddress();
  const timelockConstructorArgs = [0, [], [], adminAddress];
  const timelock = await deployer.deploy(timelockContract, timelockConstructorArgs);
  const timeLockAddress = await timelock.getAddress();
  console.log(`${contractName} TimelockController contract was deployed to ${timeLockAddress}`);

  console.log("Deploying " + contractName + "...");

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [contractName, tokenAddress, timeLockAddress, votingDelay, votingPeriod, proposalThreshold, initialQuorum, initialLateQuorum];
  const protocolGovernor = await deployer.deploy(contract, constructorArgs);

  const contractAddress = await protocolGovernor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const theToken = await protocolGovernor.token();
  console.log(`The ${contractName} Token is set to: ${theToken}`);

  (await timelock.grantRole(await timelock.PROPOSER_ROLE(), contractAddress)).wait();
  (await timelock.grantRole(await timelock.CANCELLER_ROLE(), contractAddress)).wait();
  (await timelock.grantRole(await timelock.EXECUTOR_ROLE(), contractAddress)).wait();
  console.log(`Timelock PROPOSER, CANCELLER, and EXECUTOR roles granted to ${contractName} contract`);
  (await timelock.renounceRole(await timelock.TIMELOCK_ADMIN_ROLE(), adminAddress)).wait();
  console.log(`ADMIN Role renounced for ${contractName} TimelockController contract (now self-administered)`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
