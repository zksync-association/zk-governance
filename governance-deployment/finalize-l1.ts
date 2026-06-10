#!/usr/bin/env ts-node
/**
 * finalize-l1 — given the Security-Council governance key (the EOA that is the sole owner of every
 * SC member Gnosis Safe, e.g. 0xD64e136566a9E04eb05B30184fF577F52682D182), approve a protocol
 * upgrade in the L1 ProtocolUpgradeHandler and (optionally) execute it.
 *
 * This is the TypeScript port of era-contracts'
 *   deploy-scripts/Utils.sol :: securityCouncilApproveUpgrade
 * (referenced by SecurityCouncilApproveStageUpgrade.s.sol). It only works when a single EOA owns
 * all the council member safes, which is the case for this testnet deployment.
 *
 * For each SC member safe we:
 *   1. build the SecurityCouncil EIP-712 digest  = hashTypedData(ApproveUpgradeSecurityCouncil{id})
 *   2. ask the safe for its EIP-712 SafeMessage hash over abi.encode(digest)  (getMessageHash)
 *   3. sign that hash with the owner EOA -> 65-byte (r,s,v) signature
 * Then we submit (members, signatures) to SecurityCouncil.approveUpgradeSecurityCouncil, which
 * verifies each safe via EIP-1271 and forwards the approval to the handler. Finally, if an upgrade
 * proposal is supplied, we call ProtocolUpgradeHandler.execute once the upgrade is Ready.
 *
 * Env / flags:
 *   --config <file>            config JSON (default governance.json) with l1Rpc, protocolUpgradeHandler, securityCouncil
 *   --pk <key> | $GOVERNANCE_PRIVATE_KEY   the SC-owner EOA key
 *   --id <bytes32>             the upgrade id (keccak256 of the L2->L1 message); or derive from --proposal
 *   --proposal <file>          cli-vote proposal JSON (provides upgradeProposal + upgradeId); needed for --execute
 *   --execute                  also execute the upgrade after approval (requires --proposal)
 *   --dry-run                  build & print signatures without sending txs
 */
import { Command } from "commander";
import { ethers } from "ethers";
import * as fs from "fs";

const SC_ABI = [
  "function members(uint256) view returns (address)",
  "function approveUpgradeSecurityCouncil(bytes32 id, address[] signers, bytes[] signatures)",
  "function APPROVE_UPGRADE_SECURITY_COUNCIL_THRESHOLD() view returns (uint256)",
];
const SAFE_ABI = ["function getMessageHash(bytes message) view returns (bytes32)"];
const PUH_ABI = [
  "function upgradeState(bytes32) view returns (uint8)",
  "function execute((tuple(address target,uint256 value,bytes data)[] calls,address executor,bytes32 salt) proposal) payable",
  "function securityCouncil() view returns (address)",
];
const SC_SIZE = 12;
const UPGRADE_STATE = ["None", "LegalVetoPeriod", "Waiting", "ExecutionPending", "Ready", "Expired", "Done"];

interface Config {
  l1Rpc: string;
  protocolUpgradeHandler: string;
  securityCouncil: string;
}

function loadConfig(file: string): Config {
  const cfg = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!cfg.l1Rpc || !cfg.protocolUpgradeHandler || !cfg.securityCouncil) {
    throw new Error("config must include l1Rpc, protocolUpgradeHandler, securityCouncil");
  }
  return cfg;
}

async function main() {
  const program = new Command();
  program
    .requiredOption("--config <file>", "config JSON", "governance.json")
    .option("--pk <key>", "SC-owner EOA key (else $GOVERNANCE_PRIVATE_KEY)")
    .option("--id <bytes32>", "upgrade id (keccak256 of the L2->L1 message)")
    .option("--proposal <file>", "cli-vote proposal JSON (for id + execute)")
    .option("--execute", "execute the upgrade after approval", false)
    .option("--dry-run", "print signatures without sending txs", false);
  program.parse(process.argv);
  const opts = program.opts();

  const cfg = loadConfig(opts.config);
  const pk = opts.pk || process.env.GOVERNANCE_PRIVATE_KEY;
  if (!pk) throw new Error("Provide the SC-owner key via --pk or $GOVERNANCE_PRIVATE_KEY");

  const provider = new ethers.JsonRpcProvider(cfg.l1Rpc);
  const owner = new ethers.Wallet(pk, provider);
  const { chainId } = await provider.getNetwork();

  // Resolve the upgrade id and (optional) proposal struct.
  let proposalRec: any = null;
  let upgradeId: string | undefined = opts.id;
  if (opts.proposal) {
    proposalRec = JSON.parse(fs.readFileSync(opts.proposal, "utf8"));
    upgradeId = upgradeId || proposalRec.upgradeId;
  }
  if (!upgradeId) throw new Error("Provide --id or --proposal");
  upgradeId = ethers.zeroPadValue(ethers.hexlify(upgradeId), 32);
  console.log("Upgrade id:", upgradeId);

  const puh = new ethers.Contract(cfg.protocolUpgradeHandler, PUH_ABI, owner);
  const scAddr = cfg.securityCouncil;
  const sc = new ethers.Contract(scAddr, SC_ABI, owner);

  // 1. SecurityCouncil EIP-712 digest for ApproveUpgradeSecurityCouncil(id).
  const domain = { name: "SecurityCouncil", version: "1", chainId, verifyingContract: scAddr };
  const types = { ApproveUpgradeSecurityCouncil: [{ name: "id", type: "bytes32" }] };
  const digest = ethers.TypedDataEncoder.hash(domain, types, { id: upgradeId });
  console.log("SecurityCouncil approval digest:", digest);

  // The safe signs over abi.encode(digest) (a single bytes32).
  const safeMessage = ethers.AbiCoder.defaultAbiCoder().encode(["bytes32"], [digest]);

  // 2+3. For each member safe: fetch the Safe message hash and sign it with the owner key.
  const signers: string[] = [];
  const signatures: string[] = [];
  for (let i = 0; i < SC_SIZE; i++) {
    const member: string = await sc.members(i);
    const safe = new ethers.Contract(member, SAFE_ABI, provider);
    const safeMsgHash: string = await safe.getMessageHash(safeMessage);
    // sign the raw 32-byte safe message hash (no EIP-191 prefix) -> r,s,v
    const sig = owner.signingKey.sign(safeMsgHash);
    const packed = ethers.concat([sig.r, sig.s, ethers.toBeHex(sig.v, 1)]);
    signers.push(member);
    signatures.push(packed);
  }
  console.log(`Built ${signatures.length} member signatures (threshold ${await sc.APPROVE_UPGRADE_SECURITY_COUNCIL_THRESHOLD()}).`);

  if (opts.dryRun) {
    console.log(JSON.stringify({ upgradeId, digest, signers, signatures }, null, 2));
    return;
  }

  // Pre-flight: the handler must consider the upgrade as Waiting for SC approval.
  const stateBefore = Number(await puh.upgradeState(upgradeId));
  console.log("Handler upgrade state:", UPGRADE_STATE[stateBefore] ?? stateBefore);

  // 4. Submit the approval (SecurityCouncil verifies each safe via EIP-1271, then forwards).
  console.log("Submitting approveUpgradeSecurityCouncil ...");
  const tx = await sc.approveUpgradeSecurityCouncil(upgradeId, signers, signatures);
  console.log("  tx:", tx.hash);
  await tx.wait();
  console.log("Approved. Handler state:", UPGRADE_STATE[Number(await puh.upgradeState(upgradeId))]);

  // 5. Optionally execute the upgrade.
  if (opts.execute) {
    if (!proposalRec?.upgradeProposal) throw new Error("--execute requires --proposal with upgradeProposal");
    const up = proposalRec.upgradeProposal;
    const tuple = [
      up.calls.map((c: any) => [c.target, BigInt(c.value), c.data]),
      up.executor,
      up.salt,
    ];
    const state = Number(await puh.upgradeState(upgradeId));
    if (UPGRADE_STATE[state] !== "Ready") {
      console.log(`Upgrade not Ready yet (state ${UPGRADE_STATE[state]}); skipping execute. Re-run --execute later.`);
      return;
    }
    console.log("Executing upgrade ...");
    const ex = await puh.execute(tuple);
    console.log("  tx:", ex.hash);
    await ex.wait();
    console.log("Executed. Handler state:", UPGRADE_STATE[Number(await puh.upgradeState(upgradeId))]);
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
