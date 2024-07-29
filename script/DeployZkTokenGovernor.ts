import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const contractName = "ZkTokenGovernor";
const tokenAddress = "0x0c7aA7b953217E8409D3280215293036cEd702A9";  // TODO: We'll need to deploy this contract first to get the actual address
const votingDelay = 60 * 15; // For test purposes, 15 minutes
const votingPeriod = 60 * 15; // For test purposes, 15 minutes
const proposalThreshold = 10; // For testing purposes, actual deployment will need real values
const initialQuorum = 100; // For testing purposes, actual deployment will need real values
const initialLateQuorum = 60 * 15; // For test purposes, 15 minutes
const vetoGuardian = "0xCE9e6063674DC585F6F3c7eaBe82B9936143Ba6C"; // TODO: We'll need a real address for this.. currently using a hardhat placeholder
const proposeGuardian = "0xCE9e6063674DC585F6F3c7eaBe82B9936143Ba6C"; // TODO: We'll need a real address for this.. currently using a hardhat placeholder
const initialIsProposeGuarded = false;
async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  // deploy timelock controller for the token governor
  console.log(`Deploying ${contractName} TimelockController contract...`);
  const timelockContract = await deployer.loadArtifact("TimelockController");
  const adminAddress = await zkWallet.getAddress();
  const timelockConstructorArgs = [0, [], [], adminAddress];
  const timelock = await deployer.deploy(timelockContract, timelockConstructorArgs);
  const timeLockAddress = await timelock.getAddress();
  console.log(`${contractName} TimelockController contract was deployed to ${timeLockAddress}`);

  console.log("Deploying " + contractName + "...");

  const contract = await deployer.loadArtifact(contractName);
  const argStruct = {
      name: contractName,
      token: tokenAddress,
      timelock: timeLockAddress,
      initialVotingDelay: votingDelay,
      initialVotingPeriod: votingPeriod,
      initialProposalThreshold: proposalThreshold,
      initialQuorum: initialQuorum,
      initialVoteExtension: initialLateQuorum,
      vetoGuardian: vetoGuardian,
      proposeGuardian: proposeGuardian,
      isProposeGuarded: initialIsProposeGuarded
  };
  const constructorArgs = [argStruct];
  const tokenGovernor = await deployer.deploy(contract, constructorArgs);

  const contractAddress = await tokenGovernor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const theToken = await tokenGovernor.token();
  console.log(`The Token is set to: ${theToken}`);

  await timelock.grantRole(await timelock.PROPOSER_ROLE(), contractAddress);
  await timelock.grantRole(await timelock.CANCELLER_ROLE(), contractAddress);
  await timelock.grantRole(await timelock.EXECUTOR_ROLE(), contractAddress);
  console.log(`Timelock PROPOSER, CANCELLER, and EXECUTOR roles granted to ${contractName} contract`);
  await timelock.renounceRole(await timelock.TIMELOCK_ADMIN_ROLE(), adminAddress);
  console.log(`ADMIN Role renounced for ${contractName} TimelockController contract (now self-administered)`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
