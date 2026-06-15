#!/usr/bin/env ts-node
/**
 * deploy-l2.ts — deploy the full L2 governance stack on the ZKsync Era testnet using zksync-ethers
 * directly (no hardhat-zksync-upgradable, which stalls against this chain). Deploys:
 *   1. ZkTokenV2 implementation behind a TransparentUpgradeableProxy (OZ v4.9), initialized with
 *      the supermajority mint to the deployer; then calls initializeV2 (the production V2 marker).
 *   2. TimelockController (self-administered after wiring) — this is the L1 `L2_PROTOCOL_GOVERNOR`.
 *   3. ZkProtocolGovernor wired to the token + timelock; grants it the timelock roles; renounces
 *      the deployer's timelock admin.
 *   4. Self-delegates the deployer's voting power.
 *
 * Env:
 *   DEPLOYER_PRIVATE_KEY  deployer/user key (receives the minted ZK)
 *   L2_RPC                ZKsync Era testnet RPC
 *   L2_OUT                output address-book JSON path
 *   ZK_MINT_AMOUNT, GOV_VOTING_DELAY, GOV_VOTING_PERIOD, GOV_PROPOSAL_THRESHOLD, GOV_QUORUM,
 *   GOV_VOTE_EXTENSION    (optional, see defaults below)
 */
import { Provider, Wallet, ContractFactory, Contract } from "zksync-ethers";
import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import { confirmResponse } from "./lib/zkwait";

const ART = path.join(__dirname, "..", "l2-contracts", "artifacts-zk");
function art(rel: string): any {
  return JSON.parse(fs.readFileSync(path.join(ART, rel), "utf8"));
}
const ARTIFACTS = {
  tokenV2: () => art("src/ZkTokenV2.sol/ZkTokenV2.json"),
  proxyAdmin: () => art("@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json"),
  proxy: () =>
    art("@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json"),
  timelock: () => art("@openzeppelin/contracts/governance/TimelockController.sol/TimelockController.json"),
  governor: () => art("src/ZkProtocolGovernor.sol/ZkProtocolGovernor.json"),
};

// Confirm a sent tx via (from, nonce) — robust against this chain's empty-block / hash quirks.
async function waitTx(provider: Provider, txResp: any, label: string): Promise<any> {
  return confirmResponse(provider, txResp, label);
}

async function deploy(wallet: Wallet, artifact: any, args: any[] = []): Promise<Contract> {
  const provider = wallet.provider as Provider;
  const factory = new ContractFactory(artifact.abi, artifact.bytecode, wallet, "create");
  // NB: zksync-ethers ContractFactory.deploy() internally calls waitForDeployment(), which waits
  // for a *subsequent* confirmation block and therefore hangs on this empty-block-free chain. We
  // build the deploy tx and send it raw, then confirm with our fast 1-confirmation poller and read
  // the real CREATE address from the receipt.
  const txReq = await factory.getDeployTransaction(...args);
  const resp = await wallet.sendTransaction(txReq);
  const rcpt = await confirmResponse(provider, resp, "deploy");
  if (!rcpt.contractAddress) throw new Error(`deploy ${rcpt.transactionHash}: receipt has no contractAddress`);
  return new Contract(ethers.getAddress(rcpt.contractAddress), artifact.abi, wallet);
}

function envInt(name: string, dflt: string): bigint {
  return BigInt(process.env[name] || dflt);
}

async function main() {
  const pk = process.env.DEPLOYER_PRIVATE_KEY;
  if (!pk) throw new Error("set DEPLOYER_PRIVATE_KEY");
  const l2Rpc = process.env.L2_RPC || "https://rpc.zksync-era-testnet.zksync.dev/";
  const outPath = process.env.L2_OUT || "deployments/l2-governance.json";

  const mintAmount = ethers.parseEther(process.env.ZK_MINT_AMOUNT || "10000000000");
  const votingDelay = envInt("GOV_VOTING_DELAY", "60");
  const votingPeriod = envInt("GOV_VOTING_PERIOD", "600");
  const proposalThreshold = ethers.parseEther(process.env.GOV_PROPOSAL_THRESHOLD || "0");
  const quorum = ethers.parseEther(process.env.GOV_QUORUM || "1");
  const voteExtension = envInt("GOV_VOTE_EXTENSION", "0");

  const provider = new Provider(l2Rpc);
  const wallet = new Wallet(pk, provider);
  const me = wallet.address;
  console.log("Deployer / mint receiver:", me);
  console.log("L2 balance:", ethers.formatEther(await provider.getBalance(me)), "ETH");

  // 1. Token: ZkTokenV2 impl behind a transparent proxy.
  const tokenV2Art = ARTIFACTS.tokenV2();
  console.log("Deploying ZkTokenV2 implementation ...");
  const impl = await deploy(wallet, tokenV2Art);
  const implAddr = await impl.getAddress();
  console.log("  impl:", implAddr);

  console.log("Deploying ProxyAdmin ...");
  const proxyAdmin = await deploy(wallet, ARTIFACTS.proxyAdmin());
  const proxyAdminAddr = await proxyAdmin.getAddress();
  console.log("  ProxyAdmin:", proxyAdminAddr);

  const tokenIface = new ethers.Interface(tokenV2Art.abi);
  const initData = tokenIface.encodeFunctionData("initialize", [me, me, mintAmount]);
  console.log(`Deploying TransparentUpgradeableProxy (mint ${ethers.formatEther(mintAmount)} ZK -> ${me}) ...`);
  const proxy = await deploy(wallet, ARTIFACTS.proxy(), [implAddr, proxyAdminAddr, initData]);
  const tokenAddress = await proxy.getAddress();
  console.log("  ZkToken proxy:", tokenAddress);

  const token = new Contract(tokenAddress, tokenV2Art.abi, wallet);
  console.log("Calling initializeV2 ...");
  await waitTx(provider, await token.initializeV2(), "initializeV2");
  console.log("  name/symbol:", await token.name(), await token.symbol());
  console.log("  totalSupply:", ethers.formatEther(await token.totalSupply()));

  // 2. Timelock.
  console.log("Deploying TimelockController ...");
  const timelock = await deploy(wallet, ARTIFACTS.timelock(), [0, [], [], me]);
  const timelockAddress = await timelock.getAddress();
  console.log("  TimelockController:", timelockAddress);

  // 3. Governor.
  console.log("Deploying ZkProtocolGovernor ...");
  const blockBeforeGov = await provider.getBlockNumber();
  const governor = await deploy(wallet, ARTIFACTS.governor(), [
    "ZkProtocolGovernor",
    tokenAddress,
    timelockAddress,
    votingDelay,
    votingPeriod,
    proposalThreshold,
    quorum,
    voteExtension,
  ]);
  const governorAddress = await governor.getAddress();
  const governorDeployBlock = blockBeforeGov; // lower bound for event scans
  console.log("  ZkProtocolGovernor:", governorAddress, "(block", governorDeployBlock + ")");

  // 4. Wire timelock roles to the governor; renounce deployer admin.
  console.log("Wiring timelock roles ...");
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();
  const TIMELOCK_ADMIN_ROLE = await timelock.TIMELOCK_ADMIN_ROLE();
  await waitTx(provider, await timelock.grantRole(PROPOSER_ROLE, governorAddress), "grant PROPOSER");
  await waitTx(provider, await timelock.grantRole(EXECUTOR_ROLE, governorAddress), "grant EXECUTOR");
  await waitTx(provider, await timelock.grantRole(CANCELLER_ROLE, governorAddress), "grant CANCELLER");
  await waitTx(provider, await timelock.renounceRole(TIMELOCK_ADMIN_ROLE, me), "renounce admin");
  console.log("  done.");

  // 5. Self-delegate so the deployer's balance is active voting power.
  console.log("Self-delegating ...");
  await waitTx(provider, await token.delegate(me), "delegate");
  console.log("  votes:", ethers.formatEther(await token.getVotes(me)));

  const out = {
    chainId: Number((await provider.getNetwork()).chainId),
    deployer: me,
    zkToken: tokenAddress,
    zkTokenImpl: implAddr,
    zkTokenProxyAdmin: proxyAdminAddr,
    timelock: timelockAddress,
    governor: governorAddress,
    governorDeployBlock,
    mintAmount: mintAmount.toString(),
    votingDelay: Number(votingDelay),
    votingPeriod: Number(votingPeriod),
    quorum: quorum.toString(),
  };
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("\nWrote", outPath);
  console.log(JSON.stringify(out, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
