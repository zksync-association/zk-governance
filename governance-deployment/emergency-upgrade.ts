#!/usr/bin/env ts-node
/**
 * emergency-upgrade.ts — execute an EMERGENCY protocol upgrade through the EmergencyUpgradeBoard.
 *
 * TypeScript port of era-contracts' `Utils.executeEmergencyProtocolUpgrade`
 * (the helper behind the `SecurityCouncilEmergencyStageUpgrade` forge script). An emergency upgrade
 * bypasses the L2 vote / timelock and executes immediately, but requires the joint approval of all
 * three bodies — Guardians (≥5 of 8), Security Council (≥9 of 12) and the ZK Foundation — expressed
 * as EIP-712 signatures over the upgrade id.
 *
 * Given the upgrade calls (a `sample-upgrade.json`-style file) and the governance key, it:
 *   1. builds the UpgradeProposal { calls, salt, executor = EmergencyUpgradeBoard } and id = keccak256(abi.encode(it));
 *   2. for each body, builds the board's EIP-712 digest and signs it with each member Safe:
 *        guardiansDigest        = EIP712(board)."ExecuteEmergencyUpgradeGuardians(bytes32 id)"
 *        securityCouncilDigest  = EIP712(board)."ExecuteEmergencyUpgradeSecurityCouncil(bytes32 id)"
 *        zkFoundationDigest     = EIP712(board)."ExecuteEmergencyUpgradeZKFoundation(bytes32 id)"
 *      For Guardians/SecurityCouncil it signs every member Safe's `getMessageHash(abi.encode(digest))`
 *      and ABI-encodes (members[], sigs[]) (the multisig validates them via EIP-1271 + checkSignatures);
 *      for the ZK Foundation it signs the single Safe's message hash (raw r‖s‖v).
 *   3. calls `EmergencyUpgradeBoard.executeEmergencyUpgrade(calls, salt, guardiansSigs, scSigs, zkfSig)`,
 *      which verifies all three and forwards to `ProtocolUpgradeHandler.executeEmergencyUpgrade`.
 *
 * Like finalize-l1, this assumes the member Safes (SC, Guardians, ZK Foundation) are 1-of-1 Gnosis
 * Safes owned by one EOA (the key passed here) — verify with verify-governance.ts. If different
 * Safes have different owners, sign each with its owner's key (extend `signSafe` accordingly).
 *
 * Usage:
 *   emergency-upgrade.ts --config governance.json --pk 0x<safe-owner> --calls upgrade.json [--dry-run]
 */
import { Command } from "commander";
import { ethers } from "ethers";
import * as fs from "fs";
import { normalizeProposal, encodeUpgradeProposal } from "./lib/upgrade";

const PUH_ABI = [
  "function emergencyUpgradeBoard() view returns (address)",
  "function securityCouncil() view returns (address)",
  "function guardians() view returns (address)",
  "function upgradeState(bytes32) view returns (uint8)",
];
const BOARD_ABI = [
  "function ZK_FOUNDATION_SAFE() view returns (address)",
  "function executeEmergencyUpgrade(tuple(address target,uint256 value,bytes data)[] calls, bytes32 salt, bytes guardiansSignatures, bytes securityCouncilSignatures, bytes zkFoundationSignatures)",
];
const MEMBERS_ABI = ["function members(uint256) view returns (address)"];
const SAFE_ABI = ["function getMessageHash(bytes message) view returns (bytes32)"];

const TYPES = {
  guardians: { ExecuteEmergencyUpgradeGuardians: [{ name: "id", type: "bytes32" }] },
  securityCouncil: { ExecuteEmergencyUpgradeSecurityCouncil: [{ name: "id", type: "bytes32" }] },
  zkFoundation: { ExecuteEmergencyUpgradeZKFoundation: [{ name: "id", type: "bytes32" }] },
};

async function readMembers(c: ethers.Contract): Promise<string[]> {
  const out: string[] = [];
  for (let i = 0; i < 100; i++) {
    try { out.push(ethers.getAddress(await c.members(i))); } catch { break; }
  }
  return out;
}

async function main() {
  const program = new Command();
  program
    .requiredOption("--config <file>", "config JSON (l1Rpc, protocolUpgradeHandler)", "governance.json")
    .requiredOption("--calls <file>", "upgrade calls JSON (sample-upgrade.json format: calls[], salt)")
    .option("--pk <key>", "common Safe-owner key (else $GOVERNANCE_PRIVATE_KEY)")
    .option("--dry-run", "build + print signatures without sending the tx", false);
  program.parse(process.argv);
  const opts = program.opts();

  const cfg = JSON.parse(fs.readFileSync(opts.config, "utf8"));
  const pk = opts.pk || process.env.GOVERNANCE_PRIVATE_KEY;
  if (!pk) throw new Error("provide the Safe-owner key via --pk or $GOVERNANCE_PRIVATE_KEY");
  const provider = new ethers.JsonRpcProvider(cfg.l1Rpc);
  const owner = new ethers.Wallet(pk, provider);
  const { chainId } = await provider.getNetwork();

  const puh = new ethers.Contract(ethers.getAddress(cfg.protocolUpgradeHandler), PUH_ABI, provider);
  const boardAddr = ethers.getAddress(await puh.emergencyUpgradeBoard());
  const board = new ethers.Contract(boardAddr, BOARD_ABI, provider);
  const scAddr = ethers.getAddress(await puh.securityCouncil());
  const gAddr = ethers.getAddress(await puh.guardians());
  const zkfAddr = ethers.getAddress(await board.ZK_FOUNDATION_SAFE());

  // 1. Proposal + id (executor MUST be the board, matching EmergencyUpgradeBoard.executeEmergencyUpgrade).
  const spec = JSON.parse(fs.readFileSync(opts.calls, "utf8"));
  const np = normalizeProposal(spec);
  const proposal = { calls: np.calls, executor: boardAddr, salt: np.salt };
  const id = ethers.keccak256(encodeUpgradeProposal(proposal));
  console.log(`EmergencyUpgradeBoard: ${boardAddr}`);
  console.log(`Upgrade id:            ${id}`);
  console.log(`Signer (Safe owner):   ${owner.address}\n`);

  const domain = { name: "EmergencyUpgradeBoard", version: "1", chainId, verifyingContract: boardAddr };
  const digestFor = (types: any) => ethers.TypedDataEncoder.hash(domain, types, { id });

  // Sign a Safe's EIP-712 message hash over abi.encode(digest) with the owner key (r‖s‖v).
  const signSafe = async (safeAddr: string, digest: string): Promise<string> => {
    const safeMsgHash: string = await new ethers.Contract(safeAddr, SAFE_ABI, provider).getMessageHash(
      ethers.AbiCoder.defaultAbiCoder().encode(["bytes32"], [digest])
    );
    const sig = owner.signingKey.sign(safeMsgHash);
    return ethers.concat([sig.r, sig.s, ethers.toBeHex(sig.v, 1)]);
  };

  // 2a. Guardians (all members, ascending) — abi.encode(members[], sigs[]).
  const gMembers = await readMembers(new ethers.Contract(gAddr, MEMBERS_ABI, provider));
  const gDigest = digestFor(TYPES.guardians);
  const gSigs = await Promise.all(gMembers.map((m) => signSafe(m, gDigest)));
  const guardiansSignatures = ethers.AbiCoder.defaultAbiCoder().encode(["address[]", "bytes[]"], [gMembers, gSigs]);

  // 2b. Security Council (all members) — abi.encode(members[], sigs[]).
  const scMembers = await readMembers(new ethers.Contract(scAddr, MEMBERS_ABI, provider));
  const scDigest = digestFor(TYPES.securityCouncil);
  const scSigs = await Promise.all(scMembers.map((m) => signSafe(m, scDigest)));
  const securityCouncilSignatures = ethers.AbiCoder.defaultAbiCoder().encode(["address[]", "bytes[]"], [scMembers, scSigs]);

  // 2c. ZK Foundation (single Safe) — raw r‖s‖v.
  const zkFoundationSignature = await signSafe(zkfAddr, digestFor(TYPES.zkFoundation));

  console.log(`Guardians:       ${gMembers.length} member sigs (threshold 5)`);
  console.log(`SecurityCouncil: ${scMembers.length} member sigs (threshold 9)`);
  console.log(`ZK Foundation:   1 sig (${zkfAddr})`);

  const callsTuple = np.calls.map((c) => [c.target, BigInt(c.value), c.data]);

  if (opts.dryRun) {
    console.log("\n[dry-run] not sending. Signature blobs:");
    console.log(JSON.stringify({ id, guardiansSignatures, securityCouncilSignatures, zkFoundationSignature }, null, 2));
    return;
  }

  console.log("\nSubmitting executeEmergencyUpgrade ...");
  const boardW = new ethers.Contract(boardAddr, BOARD_ABI, owner);
  const tx = await boardW.executeEmergencyUpgrade(
    callsTuple, np.salt, guardiansSignatures, securityCouncilSignatures, zkFoundationSignature
  );
  console.log("  tx:", tx.hash);
  await tx.wait();
  const state = Number(await puh.upgradeState(id));
  console.log(`Done. Upgrade state: ${state} (7=Done means executed).`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
