#!/usr/bin/env ts-node
/**
 * cli-vote — manage ZKsync protocol-upgrade votes on the L2 ZkProtocolGovernor in a testnet
 * environment. A "vote" is an OpenZeppelin Governor proposal whose single action sends the
 * encoded protocol UpgradeProposal as an L2->L1 message (via the L1Messenger system contract).
 * Once executed on L2, that message can be relayed to the L1 ProtocolUpgradeHandler.
 *
 * Connection details live in a JSON config (default ./governance.json); the signing key comes
 * from $PRIVATE_KEY (or --pk). See README-cli-vote.md for usage and an end-to-end example.
 *
 * Commands:
 *   list                                  List proposals discovered on-chain (+ local store)
 *   create --calls <file> [--description] Create a vote from a JSON file of L1 calls
 *   vote --proposal <id> [--support for|against|abstain]
 *   status --proposal <id>                Show governor state, tallies and the L2->L1 message
 *   queue --proposal <id>                 Queue a Succeeded proposal in the timelock
 *   execute --proposal <id>               Execute a Queued proposal (emits the L2->L1 message)
 *   message --proposal <id>               Print/verify the emitted L2->L1 upgrade message
 *   prove --proposal <id>                 Fetch the L1 inclusion proof params (after batch seal)
 */
import { Command } from "commander";
import { Provider, Wallet, types } from "zksync-ethers";
import { ethers } from "ethers";
import * as fs from "fs";
import * as path from "path";
import {
  normalizeProposal,
  buildGovernorProposal,
  encodeUpgradeProposal,
  L2_MESSENGER,
} from "./lib/upgrade";
import { confirmResponse } from "./lib/zkwait";

const GOVERNOR_ABI = [
  "function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) returns (uint256)",
  "function castVote(uint256 proposalId, uint8 support) returns (uint256)",
  "function castVoteWithReason(uint256 proposalId, uint8 support, string reason) returns (uint256)",
  "function state(uint256 proposalId) view returns (uint8)",
  "function proposalSnapshot(uint256 proposalId) view returns (uint256)",
  "function proposalDeadline(uint256 proposalId) view returns (uint256)",
  "function proposalProposer(uint256 proposalId) view returns (address)",
  "function proposalEta(uint256 proposalId) view returns (uint256)",
  "function proposalVotes(uint256 proposalId) view returns (uint256 against, uint256 forVotes, uint256 abstain)",
  "function quorum(uint256 timepoint) view returns (uint256)",
  "function clock() view returns (uint48)",
  "function hashProposal(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) view returns (uint256)",
  "function queue(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) returns (uint256)",
  "function execute(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) payable returns (uint256)",
  "event ProposalCreated(uint256 proposalId, address proposer, address[] targets, uint256[] values, string[] signatures, bytes[] calldatas, uint256 voteStart, uint256 voteEnd, string description)",
];

const L1_MESSAGE_SENT_TOPIC = ethers.id("L1MessageSent(address,bytes32,bytes)");

const STATE_NAMES = [
  "Pending",
  "Active",
  "Canceled",
  "Defeated",
  "Succeeded",
  "Queued",
  "Expired",
  "Executed",
];
const SUPPORT: Record<string, number> = { against: 0, for: 1, abstain: 2 };

interface Config {
  l2Rpc: string;
  l1Rpc?: string;
  governor: string;
  timelock?: string;
  zkToken?: string;
  protocolUpgradeHandler?: string;
  governorDeployBlock?: number;
}

function loadConfig(file: string): Config {
  const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!cfg.l2Rpc || !cfg.governor) throw new Error("config must include l2Rpc and governor");
  return cfg;
}

function storeDir(): string {
  const d = path.join(__dirname, "proposals");
  fs.mkdirSync(d, { recursive: true });
  return d;
}
function storePath(id: string): string {
  return path.join(storeDir(), `${id}.json`);
}
function saveProposal(rec: any) {
  fs.writeFileSync(storePath(rec.proposalId), JSON.stringify(rec, null, 2));
}
function loadProposal(id: string): any | null {
  const p = storePath(id);
  return fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, "utf8")) : null;
}

function getProvider(cfg: Config) {
  return new Provider(cfg.l2Rpc);
}

// Confirm a sent tx via (from, nonce) — robust against this chain's empty-block / hash quirks.
async function waitTx(provider: Provider, txResp: any, label = "tx") {
  return confirmResponse(provider, txResp, label);
}
function getWallet(cfg: Config, opts: any) {
  const pk = opts.pk || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("Provide a key via $PRIVATE_KEY or --pk");
  return new Wallet(pk, getProvider(cfg));
}
function governorRead(cfg: Config) {
  return new ethers.Contract(cfg.governor, GOVERNOR_ABI, getProvider(cfg));
}

/** Recover a proposal's on-chain args (targets/values/calldatas/description) from local store
 *  first, else by scanning ProposalCreated events in <=10k-block windows. */
async function recoverProposal(cfg: Config, id: string): Promise<any> {
  const local = loadProposal(id);
  if (local) return local;
  const provider = getProvider(cfg);
  const gov = governorRead(cfg);
  const latest = await provider.getBlockNumber();
  const start = cfg.governorDeployBlock ?? Math.max(0, latest - 200000);
  const step = 10000;
  for (let from = start; from <= latest; from += step) {
    const to = Math.min(from + step - 1, latest);
    const logs = await gov.queryFilter(gov.filters.ProposalCreated(), from, to);
    for (const log of logs as any[]) {
      if (log.args.proposalId.toString() === id) {
        return {
          proposalId: id,
          targets: log.args.targets,
          values: log.args.values.map((v: bigint) => v.toString()),
          calldatas: log.args.calldatas,
          description: log.args.description,
        };
      }
    }
  }
  throw new Error(`Proposal ${id} not found on-chain or in local store`);
}

function descriptionHash(rec: any): string {
  return ethers.id(rec.description ?? "");
}

async function cmdList(cfg: Config) {
  const provider = getProvider(cfg);
  const gov = governorRead(cfg);
  const latest = await provider.getBlockNumber();
  const start = cfg.governorDeployBlock ?? Math.max(0, latest - 200000);
  const step = 10000;
  const seen = new Set<string>();
  const rows: any[] = [];
  for (let from = start; from <= latest; from += step) {
    const to = Math.min(from + step - 1, latest);
    const logs = await gov.queryFilter(gov.filters.ProposalCreated(), from, to);
    for (const log of logs as any[]) {
      const id = log.args.proposalId.toString();
      if (seen.has(id)) continue;
      seen.add(id);
      const state = Number(await gov.state(id));
      rows.push({ id, state: STATE_NAMES[state], description: log.args.description, block: log.blockNumber });
    }
  }
  // include any locally stored proposals not yet found in events
  for (const f of fs.readdirSync(storeDir())) {
    const id = f.replace(/\.json$/, "");
    if (!seen.has(id)) {
      let state = "?";
      try {
        state = STATE_NAMES[Number(await gov.state(id))];
      } catch {}
      const rec = loadProposal(id);
      rows.push({ id, state, description: rec?.description, block: "(local)" });
    }
  }
  if (rows.length === 0) {
    console.log("No proposals found.");
    return;
  }
  for (const r of rows) {
    console.log(`\nProposal ${r.id}`);
    console.log(`  state:       ${r.state}`);
    console.log(`  description: ${r.description ?? ""}`);
    console.log(`  createdBlock:${r.block}`);
  }
}

async function cmdCreate(cfg: Config, opts: any) {
  const wallet = getWallet(cfg, opts);
  const spec = JSON.parse(fs.readFileSync(opts.calls, "utf8"));
  const description = opts.description || spec.description || `Protocol upgrade ${new Date().toISOString()}`;
  const proposal = normalizeProposal(spec);
  const built = buildGovernorProposal(proposal);

  const gov = new ethers.Contract(cfg.governor, GOVERNOR_ABI, wallet);
  const proposalId = (
    await gov.hashProposal(built.targets, built.values, built.calldatas, ethers.id(description))
  ).toString();

  console.log("Submitting proposal ...");
  console.log("  L1 upgrade id (keccak of message):", built.id);
  const tx = await gov.propose(built.targets, built.values, built.calldatas, description);
  console.log("  tx:", tx.hash);
  const rcpt = await waitTx(getProvider(cfg), tx, "propose");
  console.log(`  mined in block ${rcpt.blockNumber}`);

  saveProposal({
    proposalId,
    targets: built.targets,
    values: built.values.map((v) => v.toString()),
    calldatas: built.calldatas,
    description,
    message: built.message,
    upgradeId: built.id,
    upgradeProposal: {
      calls: proposal.calls.map((c) => ({ target: c.target, value: c.value.toString(), data: c.data })),
      executor: proposal.executor,
      salt: proposal.salt,
    },
    createdBlock: rcpt.blockNumber,
  });
  console.log("\nProposal created:");
  console.log("  proposalId:", proposalId);
  console.log("  upgradeId :", built.id);
  console.log("Saved to", storePath(proposalId));
}

async function cmdVote(cfg: Config, opts: any) {
  const wallet = getWallet(cfg, opts);
  const gov = new ethers.Contract(cfg.governor, GOVERNOR_ABI, wallet);
  const support = SUPPORT[(opts.support || "for").toLowerCase()];
  if (support === undefined) throw new Error("--support must be for|against|abstain");
  const state = Number(await gov.state(opts.proposal));
  console.log(`Proposal state: ${STATE_NAMES[state]}`);
  const tx = opts.reason
    ? await gov.castVoteWithReason(opts.proposal, support, opts.reason)
    : await gov.castVote(opts.proposal, support);
  console.log("  vote tx:", tx.hash);
  await waitTx(getProvider(cfg), tx, "vote");
  const [against, forVotes, abstain] = await gov.proposalVotes(opts.proposal);
  console.log(`Tallies — for: ${ethers.formatEther(forVotes)} against: ${ethers.formatEther(against)} abstain: ${ethers.formatEther(abstain)}`);
}

async function cmdStatus(cfg: Config, opts: any) {
  const gov = governorRead(cfg);
  const id = opts.proposal;
  const state = Number(await gov.state(id));
  console.log(`Proposal ${id}`);
  console.log(`  state:    ${STATE_NAMES[state]}`);
  try {
    const snap = await gov.proposalSnapshot(id);
    const deadline = await gov.proposalDeadline(id);
    const clock = await gov.clock();
    console.log(`  clock:    ${clock} (snapshot ${snap}, deadline ${deadline})`);
    const [against, forVotes, abstain] = await gov.proposalVotes(id);
    console.log(`  votes:    for ${ethers.formatEther(forVotes)} / against ${ethers.formatEther(against)} / abstain ${ethers.formatEther(abstain)}`);
    console.log(`  quorum:   ${ethers.formatEther(await gov.quorum(snap))}`);
    const eta = await gov.proposalEta(id);
    if (eta > 0n) console.log(`  eta:      ${eta}`);
  } catch (e: any) {
    console.log("  (extra fields unavailable):", e.message);
  }
  const rec = loadProposal(id);
  if (rec) {
    console.log(`  upgradeId:${rec.upgradeId}`);
    console.log(`  L2->L1 message bytes (${(rec.message.length - 2) / 2} bytes): ${rec.message.slice(0, 66)}...`);
  }
}

async function cmdQueue(cfg: Config, opts: any) {
  const wallet = getWallet(cfg, opts);
  const rec = await recoverProposal(cfg, opts.proposal);
  const gov = new ethers.Contract(cfg.governor, GOVERNOR_ABI, wallet);
  const tx = await gov.queue(rec.targets, rec.values, rec.calldatas, descriptionHash(rec));
  console.log("  queue tx:", tx.hash);
  await waitTx(getProvider(cfg), tx, "queue");
  console.log("Queued.");
}

async function cmdExecute(cfg: Config, opts: any) {
  const wallet = getWallet(cfg, opts);
  const rec = await recoverProposal(cfg, opts.proposal);
  const gov = new ethers.Contract(cfg.governor, GOVERNOR_ABI, wallet);
  const tx = await gov.execute(rec.targets, rec.values, rec.calldatas, descriptionHash(rec));
  console.log("  execute tx:", tx.hash);
  const rcpt = await waitTx(getProvider(cfg), tx, "execute");
  console.log(`Executed in block ${rcpt.blockNumber}. tx: ${tx.hash}`);
  // persist the execution tx hash for `message`/`prove`
  if (loadProposal(opts.proposal)) {
    const r = loadProposal(opts.proposal);
    r.executeTx = tx.hash;
    saveProposal(r);
  }
  console.log("Run `cli-vote message --proposal", opts.proposal, "` to inspect the L2->L1 message.");
}

/** Find the L1MessageSent log in the execution receipt and verify it matches the encoded proposal. */
async function cmdMessage(cfg: Config, opts: any) {
  const provider = getProvider(cfg);
  const rec = loadProposal(opts.proposal);
  const txHash = opts.tx || rec?.executeTx;
  if (!txHash) throw new Error("No execution tx known; pass --tx <hash> or run execute first");
  const rcpt: any = await provider.send("eth_getTransactionReceipt", [txHash]);
  if (!rcpt) throw new Error("Execution receipt not found");
  const log = (rcpt.logs as any[]).find(
    (l) => l.address.toLowerCase() === L2_MESSENGER.toLowerCase() && l.topics[0] === L1_MESSAGE_SENT_TOPIC
  );
  if (!log) throw new Error("No L1MessageSent event from L1Messenger in this tx");
  const [emitted] = ethers.AbiCoder.defaultAbiCoder().decode(["bytes"], log.data);
  console.log("Emitted L2->L1 message sender (topic):", "0x" + log.topics[1].slice(26));
  console.log("Emitted message hash (topic):", log.topics[2]);
  console.log("Emitted message bytes:", emitted);
  if (rec) {
    const match = emitted.toLowerCase() === rec.message.toLowerCase();
    console.log("Matches locally-encoded UpgradeProposal:", match);
    console.log("Upgrade id (keccak256 of message):", ethers.keccak256(emitted));
    if (!match) {
      console.log("  expected:", rec.message);
    }
  }
}

/** Produce the L1 inclusion proof params for ProtocolUpgradeHandler.startUpgrade (after seal). */
async function cmdProve(cfg: Config, opts: any) {
  const provider = getProvider(cfg);
  const rec = loadProposal(opts.proposal);
  const txHash = opts.tx || rec?.executeTx;
  if (!txHash) throw new Error("No execution tx known; pass --tx <hash> or run execute first");
  const rcpt = (await provider.getTransactionReceipt(txHash)) as types.TransactionReceipt;
  // index of the L1->L2 (sendToL1) log among this tx's L2->L1 messages
  const proof = await provider.getLogProof(txHash, 0);
  if (!proof) {
    console.log("Proof not available yet — the batch is not sealed/executed on L1. Try later.");
    return;
  }
  console.log(JSON.stringify(
    {
      l2BatchNumber: rcpt.l1BatchNumber,
      l2MessageIndex: proof.id,
      l2TxNumberInBatch: rcpt.l1BatchTxIndex,
      proof: proof.proof,
      sender: cfg.timelock,
      message: rec?.message,
    },
    (_k, v) => (typeof v === "bigint" ? Number(v) : v),
    2
  ));
}

async function main() {
  const program = new Command();
  program.name("cli-vote").description("Manage ZKsync L2 protocol-upgrade votes");
  program.option("-c, --config <file>", "config JSON", "governance.json");
  program.option("--pk <key>", "signer private key (else $PRIVATE_KEY)");

  const withCfg = (fn: (cfg: Config, opts: any) => Promise<void>) => async (opts: any, cmd: any) => {
    const merged = { ...program.opts(), ...opts };
    const cfg = loadConfig(merged.config);
    await fn(cfg, merged);
  };

  program.command("list").description("List proposals").action(withCfg(cmdList));
  program
    .command("create")
    .requiredOption("--calls <file>", "JSON file with the L1 calls to perform")
    .option("--description <text>", "human description (also the dedup key)")
    .action(withCfg(cmdCreate));
  program
    .command("vote")
    .requiredOption("--proposal <id>", "proposal id")
    .option("--support <choice>", "for | against | abstain", "for")
    .option("--reason <text>", "vote reason")
    .action(withCfg(cmdVote));
  program.command("status").requiredOption("--proposal <id>", "proposal id").action(withCfg(cmdStatus));
  program.command("queue").requiredOption("--proposal <id>", "proposal id").action(withCfg(cmdQueue));
  program.command("execute").requiredOption("--proposal <id>", "proposal id").action(withCfg(cmdExecute));
  program
    .command("message")
    .requiredOption("--proposal <id>", "proposal id")
    .option("--tx <hash>", "execution tx hash")
    .action(withCfg(cmdMessage));
  program
    .command("prove")
    .requiredOption("--proposal <id>", "proposal id")
    .option("--tx <hash>", "execution tx hash")
    .action(withCfg(cmdProve));

  await program.parseAsync(process.argv);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
