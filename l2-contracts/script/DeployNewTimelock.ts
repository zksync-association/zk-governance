import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import * as hre from "hardhat";

// Before executing a real deployment, be sure to set these values as appropriate for the environment being deployed
// to. The values used in the script at the time of deployment can be checked in along with the deployment artifacts
// produced by running the scripts.
const contractName = "ZkProtocolGovernor";
const contractAddress = "0x5a6862ee581b6cDb517D24f0a69237f9D900C23C";

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

  (await timelock.grantRole(await timelock.PROPOSER_ROLE(), contractAddress)).wait();
  (await timelock.grantRole(await timelock.CANCELLER_ROLE(), contractAddress)).wait();
  (await timelock.grantRole(await timelock.EXECUTOR_ROLE(), contractAddress)).wait();
  console.log(`Timelock PROPOSER, CANCELLER, and EXECUTOR roles granted to ${contractName} contract`);
  (await timelock.renounceRole(await timelock.TIMELOCK_ADMIN_ROLE(), adminAddress)).wait();
  console.log(`ADMIN Role renounced for ${contractName} TimelockController contract (now self-administered)`);

  console.log('Verifying contract...')
  const verificationId = await hre.run("verify:verify", {
    address: timeLockAddress,
    contract: "TimelockController",
    constructorArguments: timelockConstructorArgs
  });  

  console.log('Verification id: ', verificationId);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
