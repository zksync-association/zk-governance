#!/usr/bin/env ts-node
/**
 * verify-governance.ts — independently verify a deployed ProtocolUpgradeHandler (PUH).
 *
 * Given the new PUH address, the bridgehub address and the L2 governor (timelock) address, it:
 *
 *  1. Constructor-arg check: re-derives every ecosystem address the PUH was constructed with by
 *     traversing the bridgehub, and asserts each matches what the PUH actually stores:
 *        BRIDGE_HUB            == <given bridgehub>
 *        L1_ASSET_ROUTER       == bridgehub.assetRouter()
 *        L1_NULLIFIER          == assetRouter.L1_NULLIFIER()
 *        L1_NATIVE_TOKEN_VAULT == assetRouter.nativeTokenVault()
 *        CHAIN_ASSET_HANDLER   == bridgehub.chainAssetHandler()
 *        ZKSYNC_ERA            == bridgehub.getZKChain(eraChainId)        (the chain whose diamond is ZKSYNC_ERA)
 *        CHAIN_TYPE_MANAGER    == bridgehub.chainTypeManager(eraChainId)
 *        L2_PROTOCOL_GOVERNOR  == <given L2 governor / timelock>
 *
 *  2. Governance-body wiring: SecurityCouncil / Guardians / EmergencyUpgradeBoard all point back to
 *     the PUH, and the board's SECURITY_COUNCIL / GUARDIANS / ZK_FOUNDATION_SAFE are consistent.
 *
 *  3. Safe owner check: every Security-Council member safe (12), every Guardian member safe (8) and
 *     the ZK Foundation safe are 1-of-1 Gnosis Safes controlled by the SAME EOA — which it prints.
 *
 * Usage:
 *   verify-governance.ts --config governance.json
 *   verify-governance.ts --puh 0x.. --bridgehub 0x.. --l2-gov 0x.. --l1-rpc https://..
 */
import { Command } from "commander";
import { ethers } from "ethers";
import * as fs from "fs";

const PUH_ABI = [
  "function BRIDGE_HUB() view returns (address)",
  "function CHAIN_TYPE_MANAGER() view returns (address)",
  "function ZKSYNC_ERA() view returns (address)",
  "function L1_ASSET_ROUTER() view returns (address)",
  "function L1_NULLIFIER() view returns (address)",
  "function L1_NATIVE_TOKEN_VAULT() view returns (address)",
  "function CHAIN_ASSET_HANDLER() view returns (address)",
  "function L2_PROTOCOL_GOVERNOR() view returns (address)",
  "function securityCouncil() view returns (address)",
  "function guardians() view returns (address)",
  "function emergencyUpgradeBoard() view returns (address)",
];
const BRIDGEHUB_ABI = [
  "function assetRouter() view returns (address)",
  "function chainAssetHandler() view returns (address)",
  "function getAllZKChainChainIDs() view returns (uint256[])",
  "function getZKChain(uint256 chainId) view returns (address)",
  "function chainTypeManager(uint256 chainId) view returns (address)",
];
const ASSET_ROUTER_ABI = [
  "function L1_NULLIFIER() view returns (address)",
  "function nativeTokenVault() view returns (address)",
];
const MULTISIG_ABI = [
  "function members(uint256) view returns (address)",
  "function PROTOCOL_UPGRADE_HANDLER() view returns (address)",
  "function EIP1271_THRESHOLD() view returns (uint256)",
];
const BOARD_ABI = [
  "function PROTOCOL_UPGRADE_HANDLER() view returns (address)",
  "function SECURITY_COUNCIL() view returns (address)",
  "function GUARDIANS() view returns (address)",
  "function ZK_FOUNDATION_SAFE() view returns (address)",
];
const SAFE_ABI = ["function getOwners() view returns (address[])", "function getThreshold() view returns (uint256)"];

const eq = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
let failures = 0;
function check(label: string, actual: string, expected: string) {
  const ok = eq(actual, expected);
  if (!ok) failures++;
  console.log(`  ${ok ? "OK  " : "FAIL"} ${label.padEnd(24)} ${actual}${ok ? "" : `  != expected ${expected}`}`);
}

async function readMembers(c: ethers.Contract): Promise<string[]> {
  const out: string[] = [];
  for (let i = 0; i < 100; i++) {
    try {
      out.push(ethers.getAddress(await c.members(i)));
    } catch {
      break;
    }
  }
  return out;
}

async function main() {
  const program = new Command();
  program
    .option("--config <file>", "config JSON (l1Rpc, protocolUpgradeHandler, bridgehub, timelock)", "governance.json")
    .option("--puh <addr>", "ProtocolUpgradeHandler to verify")
    .option("--bridgehub <addr>", "expected bridgehub")
    .option("--l2-gov <addr>", "expected L2 governor / timelock")
    .option("--l1-rpc <url>", "L1 RPC");
  program.parse(process.argv);
  const o = program.opts();
  const cfg = fs.existsSync(o.config) ? JSON.parse(fs.readFileSync(o.config, "utf8")) : {};

  const l1Rpc = o.l1Rpc || cfg.l1Rpc;
  const puhAddr = ethers.getAddress(o.puh || cfg.protocolUpgradeHandler);
  const bridgehubAddr = ethers.getAddress(o.bridgehub || cfg.bridgehub);
  const l2Gov = ethers.getAddress(o.l2Gov || cfg.timelock);
  const provider = new ethers.JsonRpcProvider(l1Rpc);
  const puh = new ethers.Contract(puhAddr, PUH_ABI, provider);
  const bh = new ethers.Contract(bridgehubAddr, BRIDGEHUB_ABI, provider);

  console.log(`Verifying PUH ${puhAddr}\n  bridgehub=${bridgehubAddr}  l2Gov=${l2Gov}\n`);

  // ---- 1. constructor args, re-derived from the bridgehub ----
  console.log("1) Constructor args (PUH value vs bridgehub-derived):");
  check("BRIDGE_HUB", await puh.BRIDGE_HUB(), bridgehubAddr);
  check("L2_PROTOCOL_GOVERNOR", await puh.L2_PROTOCOL_GOVERNOR(), l2Gov);
  const assetRouter = ethers.getAddress(await bh.assetRouter());
  const ar = new ethers.Contract(assetRouter, ASSET_ROUTER_ABI, provider);
  check("L1_ASSET_ROUTER", await puh.L1_ASSET_ROUTER(), assetRouter);
  check("L1_NULLIFIER", await puh.L1_NULLIFIER(), ethers.getAddress(await ar.L1_NULLIFIER()));
  check("L1_NATIVE_TOKEN_VAULT", await puh.L1_NATIVE_TOKEN_VAULT(), ethers.getAddress(await ar.nativeTokenVault()));
  check("CHAIN_ASSET_HANDLER", await puh.CHAIN_ASSET_HANDLER(), ethers.getAddress(await bh.chainAssetHandler()));

  // find the era chain (the chain whose diamond is PUH.ZKSYNC_ERA), then verify ZKSYNC_ERA + CTM via it
  const zksyncEra = ethers.getAddress(await puh.ZKSYNC_ERA());
  const chains: bigint[] = await bh.getAllZKChainChainIDs();
  let eraChainId: bigint | null = null;
  for (const id of chains) {
    try {
      if (eq(await bh.getZKChain(id), zksyncEra)) { eraChainId = id; break; }
    } catch {}
  }
  if (eraChainId === null) {
    failures++;
    console.log(`  FAIL ZKSYNC_ERA               ${zksyncEra}  (no bridgehub chain resolves to this diamond)`);
  } else {
    console.log(`  (era chainId resolved from bridgehub: ${eraChainId})`);
    check("ZKSYNC_ERA", zksyncEra, ethers.getAddress(await bh.getZKChain(eraChainId)));
    check("CHAIN_TYPE_MANAGER", await puh.CHAIN_TYPE_MANAGER(), ethers.getAddress(await bh.chainTypeManager(eraChainId)));
  }

  // ---- 2. governance-body wiring ----
  console.log("\n2) Governance bodies wired to the PUH:");
  const scAddr = ethers.getAddress(await puh.securityCouncil());
  const gAddr = ethers.getAddress(await puh.guardians());
  const boardAddr = ethers.getAddress(await puh.emergencyUpgradeBoard());
  const sc = new ethers.Contract(scAddr, MULTISIG_ABI, provider);
  const g = new ethers.Contract(gAddr, MULTISIG_ABI, provider);
  const board = new ethers.Contract(boardAddr, BOARD_ABI, provider);
  check("SecurityCouncil->PUH", await sc.PROTOCOL_UPGRADE_HANDLER(), puhAddr);
  check("Guardians->PUH", await g.PROTOCOL_UPGRADE_HANDLER(), puhAddr);
  check("Board->PUH", await board.PROTOCOL_UPGRADE_HANDLER(), puhAddr);
  check("Board.SECURITY_COUNCIL", await board.SECURITY_COUNCIL(), scAddr);
  check("Board.GUARDIANS", await board.GUARDIANS(), gAddr);
  const zkFoundation = ethers.getAddress(await board.ZK_FOUNDATION_SAFE());

  // ---- 3. safe owner check ----
  console.log("\n3) Member safes are 1-of-1 with a single common owner:");
  const scMembers = await readMembers(sc);
  const gMembers = await readMembers(g);
  console.log(`  SecurityCouncil members: ${scMembers.length}, Guardian members: ${gMembers.length}, ZkFoundation: 1`);
  const safes: { label: string; addr: string }[] = [
    ...scMembers.map((a, i) => ({ label: `SC[${i}]`, addr: a })),
    ...gMembers.map((a, i) => ({ label: `Guardian[${i}]`, addr: a })),
    { label: "ZkFoundation", addr: zkFoundation },
  ];
  const owners = new Set<string>();
  let safeFailures = 0;
  for (const s of safes) {
    const safe = new ethers.Contract(s.addr, SAFE_ABI, provider);
    let os: string[], th: bigint;
    try {
      os = await safe.getOwners();
      th = await safe.getThreshold();
    } catch {
      safeFailures++;
      console.log(`  FAIL ${s.label} ${s.addr}: not a Gnosis Safe (no getOwners)`);
      continue;
    }
    if (os.length !== 1 || th !== 1n) {
      safeFailures++;
      console.log(`  FAIL ${s.label} ${s.addr}: owners=${os.length} threshold=${th} (expected 1-of-1)`);
    } else {
      owners.add(ethers.getAddress(os[0]));
    }
  }
  failures += safeFailures;
  if (owners.size === 1 && safeFailures === 0) {
    console.log(`  OK   all ${safes.length} safes are 1-of-1 owned by the SAME EOA:`);
    console.log(`\n  >>> Common Gnosis Safe owner (EOA): ${[...owners][0]}\n`);
  } else {
    failures++;
    console.log(`  FAIL safes do not share a single owner — distinct owners: ${[...owners].join(", ") || "(none)"}`);
  }

  console.log(failures === 0 ? "VERIFICATION PASSED ✅" : `VERIFICATION FAILED ❌ (${failures} problem(s))`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
