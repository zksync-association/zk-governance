import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const contractName = "ZkGovOpsGovernor";
const tokenAddress = "0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E";
const votingDelay = 7 * 24 * 60 * 60; // 7 days
const votingPeriod = 7 * 24 * 60 * 60; // 7 days
const proposalThreshold = "21000000000000000000000000"; // Raw decimals for 21 Million (0.1% of supply)
const initialQuorum = "630000000000000000000000000"; // Raw decimals for 630 Million (3% of supply)
const initialLateQuorum = 7 * 24 * 60 * 60; // 7 days
const timelockDelay = 3 * 24 * 60 * 60; // 3 days
// L2 Alias of the L1 safe deployed at eth:0xD677e09324F8Bb3cC64F009973693f751c33A888
const initialGuardian = "0xe788e09324F8bb3cc64f009973693f751C33b999";

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!deployerPrivateKey) {
    throw "Please set DEPLOYER_PRIVATE_KEY in your .env file";
  }

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  // deploy timelock controller for the GovOps governor
  console.log(`Deploying ${contractName} TimelockController contract...`);
  const timelockContract = await deployer.loadArtifact("TimelockController");
  const adminAddress = await zkWallet.getAddress();
  const timelockConstructorArgs = [timelockDelay, [], [], adminAddress];
  const timelock = await deployer.deploy(timelockContract, timelockConstructorArgs);
  const timeLockAddress = await timelock.getAddress();
  console.log(`${contractName} Governor TimelockController contract was deployed to ${timeLockAddress}`);

  console.log("Deploying " + contractName + "...");

  const contract = await deployer.loadArtifact(contractName);
  const constructorArgs = [{
		name: contractName, 
		token: tokenAddress, 
		timelock: timeLockAddress, 
		initialVotingDelay: votingDelay, 
		initialVotingPeriod: votingPeriod, 
		initialProposalThreshold: proposalThreshold, 
		initialQuorum: initialQuorum, 
		initialVoteExtension: initialLateQuorum, 
		vetoGuardian: initialGuardian
	}];
  const govOpsGovernor = await deployer.deploy(contract, constructorArgs);

  const contractAddress = await govOpsGovernor.getAddress();
  console.log(`${contractName} was deployed to ${contractAddress}`);

  const theToken = await govOpsGovernor.token();
  console.log(`The Token is set to: ${theToken}`);

  await (await timelock.grantRole(await timelock.PROPOSER_ROLE(), contractAddress)).wait();
  await (await timelock.grantRole(await timelock.CANCELLER_ROLE(), contractAddress)).wait();
  await (await timelock.grantRole(await timelock.EXECUTOR_ROLE(), contractAddress)).wait();
  console.log(`Timelock PROPOSER, CANCELLER, and EXECUTOR roles granted to ${contractName} contract`);
  await (await timelock.renounceRole(await timelock.TIMELOCK_ADMIN_ROLE(), adminAddress)).wait();
  console.log(`ADMIN Role renounced for ${contractName} TimelockController contract (now self-administered)`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
