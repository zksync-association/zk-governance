import { config as dotEnvConfig } from "dotenv";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Contract, Wallet } from "zksync-ethers";
import { getAddress, keccak256, toUtf8Bytes } from "ethers";
import * as hre from "hardhat";

// Redeploys the ZkGovOpsGovernor as part of the guardians removal: the new instance keeps
// the live settings, token and TimelockController of the current governor, but swaps the
// immutable veto seat:
//   - VETO_GUARDIAN -> the native ZK Foundation Safe on Era (NEW_VETO_GUARDIAN)
//
// The script does NOT touch the timelock: it prints the proposal actions that must be
// passed through the *current* governor to hand the timelock roles over to the new one.
//
// Required env vars:
//   DEPLOYER_PRIVATE_KEY - deployer key
//   CURRENT_GOVERNOR     - address of the live ZkGovOpsGovernor
//   NEW_VETO_GUARDIAN    - native ZK Foundation Safe (Era) taking the veto seat
// Optional env vars:
//   NEW_GOVERNOR         - an already deployed new governor to verify and build the migration for
const contractName = "ZkGovOpsGovernor";

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw `Please set ${name} in your .env file`;
  }
  return value;
}

function requireEqual(label: string, actual: unknown, expected: unknown) {
  if (String(actual) !== String(expected)) {
    throw `New governor ${label} mismatch: expected ${expected}, got ${actual}`;
  }
}

async function main() {
  dotEnvConfig();

  const deployerPrivateKey = requireEnv("DEPLOYER_PRIVATE_KEY");
  const currentGovernorAddress = requireEnv("CURRENT_GOVERNOR");
  const newVetoGuardian = getAddress(requireEnv("NEW_VETO_GUARDIAN"));

  const zkWallet = new Wallet(deployerPrivateKey);
  const deployer = new Deployer(hre, zkWallet);

  const governorArtifact = await deployer.loadArtifact(contractName);
  const currentGovernor = new Contract(currentGovernorAddress, governorArtifact.abi, deployer.zkWallet);

  // Read the live configuration from the current governor.
  const name = await currentGovernor.name();
  const tokenAddress = await currentGovernor.token();
  const timelockAddress = await currentGovernor.timelock();
  const votingDelay = await currentGovernor.votingDelay();
  const votingPeriod = await currentGovernor.votingPeriod();
  const proposalThreshold = await currentGovernor.proposalThreshold();
  const quorum = await currentGovernor.quorum(await currentGovernor.clock());
  const lateQuorumVoteExtension = await currentGovernor.lateQuorumVoteExtension();
  const oldVetoGuardian = await currentGovernor.VETO_GUARDIAN();

  if (newVetoGuardian === getAddress(oldVetoGuardian)) {
    throw "NEW_VETO_GUARDIAN must differ from the current VETO_GUARDIAN";
  }
  // The veto seat is held by a native multisig on Era, not by an L1 address alias.
  if ((await deployer.zkWallet.provider.getCode(newVetoGuardian)) === "0x") {
    throw "NEW_VETO_GUARDIAN must be a contract (multisig) on Era";
  }

  console.log("=== Current ZkGovOpsGovernor ===");
  console.log(`Address: ${currentGovernorAddress}`);
  console.log(`Name: ${name}`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`Timelock: ${timelockAddress}`);
  console.log(`Voting delay: ${votingDelay}`);
  console.log(`Voting period: ${votingPeriod}`);
  console.log(`Proposal threshold: ${proposalThreshold}`);
  console.log(`Quorum: ${quorum}`);
  console.log(`Late quorum vote extension: ${lateQuorumVoteExtension}`);
  console.log(`Old VETO_GUARDIAN: ${oldVetoGuardian}`);
  console.log("");
  console.log(`New VETO_GUARDIAN (ZK Foundation Safe): ${newVetoGuardian}`);

  // Numbers are passed as strings: the deployment cache of hardhat-zksync-deploy can't serialize BigInts.
  const argStruct = {
    name: name,
    token: tokenAddress,
    timelock: timelockAddress,
    initialVotingDelay: votingDelay.toString(),
    initialVotingPeriod: votingPeriod.toString(),
    initialProposalThreshold: proposalThreshold.toString(),
    initialQuorum: quorum.toString(),
    initialVoteExtension: lateQuorumVoteExtension.toString(),
    vetoGuardian: newVetoGuardian,
  };
  const constructorArgs = [argStruct];

  // NEW_GOVERNOR resumes from an already deployed governor (it is still verified below).
  let newGovernorAddress: string;
  console.log("");
  if (process.env.NEW_GOVERNOR) {
    newGovernorAddress = getAddress(process.env.NEW_GOVERNOR);
    console.log(`Using the already deployed ${contractName} at ${newGovernorAddress}`);
  } else {
    console.log(`Deploying the new ${contractName}...`);
    const newGovernor = await deployer.deploy(governorArtifact, constructorArgs);
    newGovernorAddress = await newGovernor.getAddress();
    console.log(`${contractName} was deployed to ${newGovernorAddress}`);
  }
  console.log("constructor args:" + currentGovernor.interface.encodeDeploy(constructorArgs));

  // Everything but the veto seat must match the current governor.
  const deployedGovernor = new Contract(newGovernorAddress, governorArtifact.abi, deployer.zkWallet);
  requireEqual("name", await deployedGovernor.name(), name);
  requireEqual("token", await deployedGovernor.token(), tokenAddress);
  requireEqual("timelock", await deployedGovernor.timelock(), timelockAddress);
  requireEqual("voting delay", await deployedGovernor.votingDelay(), votingDelay);
  requireEqual("voting period", await deployedGovernor.votingPeriod(), votingPeriod);
  requireEqual("proposal threshold", await deployedGovernor.proposalThreshold(), proposalThreshold);
  requireEqual("quorum", await deployedGovernor.quorum(await deployedGovernor.clock()), quorum);
  requireEqual("late quorum vote extension", await deployedGovernor.lateQuorumVoteExtension(), lateQuorumVoteExtension);
  requireEqual("VETO_GUARDIAN", getAddress(await deployedGovernor.VETO_GUARDIAN()), newVetoGuardian);
  console.log("New governor settings verified against the current governor");

  // Build the timelock role migration that must be proposed on the CURRENT governor.
  const timelockArtifact = await deployer.loadArtifact("TimelockController");
  const timelock = new Contract(timelockAddress, timelockArtifact.abi, deployer.zkWallet);
  const proposerRole = await timelock.PROPOSER_ROLE();
  const cancellerRole = await timelock.CANCELLER_ROLE();
  const executorRole = await timelock.EXECUTOR_ROLE();

  // Grants first, revokes second: if execution were ever partial the timelock is never
  // left without a governor holding the roles.
  const calldatas = [
    timelock.interface.encodeFunctionData("grantRole", [proposerRole, newGovernorAddress]),
    timelock.interface.encodeFunctionData("grantRole", [cancellerRole, newGovernorAddress]),
    timelock.interface.encodeFunctionData("grantRole", [executorRole, newGovernorAddress]),
    timelock.interface.encodeFunctionData("revokeRole", [proposerRole, currentGovernorAddress]),
    timelock.interface.encodeFunctionData("revokeRole", [cancellerRole, currentGovernorAddress]),
    timelock.interface.encodeFunctionData("revokeRole", [executorRole, currentGovernorAddress]),
  ];
  const targets = calldatas.map(() => timelockAddress);
  const values = calldatas.map(() => 0n);
  const description =
    `Migrate ${contractName} timelock roles to the redeployed governor at ${newGovernorAddress} ` +
    "(guardians removal: veto seat moves to the ZK Foundation Safe)";

  console.log("");
  console.log("=== Timelock role migration (propose on the CURRENT governor) ===");
  console.log(
    JSON.stringify(
      {
        targets: targets,
        values: values.map((v) => v.toString()),
        calldatas: calldatas,
        description: description,
      },
      null,
      2
    )
  );
  console.log(`Description hash: ${keccak256(toUtf8Bytes(description))}`);
  console.log(
    "propose() calldata: " +
      currentGovernor.interface.encodeFunctionData("propose", [targets, values, calldatas, description])
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
