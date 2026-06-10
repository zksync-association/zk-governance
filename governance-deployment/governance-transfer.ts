#!/usr/bin/env ts-node
/**
 * governance-transfer.ts — migrate ownership of the ZKsync ecosystem contracts to the newly
 * deployed L1 ProtocolUpgradeHandler (PUH).
 *
 * Background: in era-contracts the ecosystem contracts are `Ownable2Step` and are controlled by
 * governance. Their current owner is either:
 *   (a) the `Governance.sol` contract (era-contracts) — whose own `owner()` is the governance EOA, or
 *   (b) the governance EOA directly.
 * Ownership migration is therefore a two-step (Ownable2Step) handover:
 *   1. the *current owner* calls `transferOwnership(PUH)`  — done here, with the governance-owner key
 *   2. the *new owner* (the PUH) calls `acceptOwnership()`  — the PUH only acts via an executed
 *      protocol upgrade, so we emit those calls as a `sample-upgrade.json`-style file that you feed
 *      to `cli-vote create --calls ...` and pass through the governor → PUH.
 *
 * This script performs step 1 (routing each transfer through `Governance.sol` when a contract is
 * owned by it, or sending a direct tx when the EOA owns it) and writes step 2 to disk.
 *
 * The ownable ecosystem contracts (per era-contracts) are: Bridgehub, ChainTypeManager,
 * L1AssetRouter, L1Nullifier, L1NativeTokenVault and ChainAssetHandler — exactly the immutables the
 * PUH already references, so we discover the target set straight from the deployed PUH.
 *
 * Usage:
 *   governance-transfer.ts --config governance.json --pk 0x<governance-owner> \
 *       [--new-owner 0x<PUH>] [--out accept-ownership.json] [--targets 0x..,0x..] [--dry-run]
 */
import { Command } from "commander";
import { ethers } from "ethers";
import * as fs from "fs";

const OWNABLE2STEP_ABI = [
  "function owner() view returns (address)",
  "function pendingOwner() view returns (address)",
  "function transferOwnership(address newOwner)",
  "function acceptOwnership()",
];
// era-contracts Governance.sol (Operation = { Call[] calls; bytes32 predecessor; bytes32 salt }).
const GOVERNANCE_ABI = [
  "function owner() view returns (address)",
  "function minDelay() view returns (uint256)",
  "function scheduleTransparent(((address target,uint256 value,bytes data)[] calls,bytes32 predecessor,bytes32 salt) operation, uint256 delay)",
  "function execute(((address target,uint256 value,bytes data)[] calls,bytes32 predecessor,bytes32 salt) operation) payable",
  "function hashOperation(((address target,uint256 value,bytes data)[] calls,bytes32 predecessor,bytes32 salt) operation) pure returns (bytes32)",
  "function isOperationReady(bytes32 id) view returns (bool)",
];
// The PUH immutables that point at the ownable ecosystem contracts.
const PUH_ABI = [
  "function BRIDGE_HUB() view returns (address)",
  "function CHAIN_TYPE_MANAGER() view returns (address)",
  "function L1_ASSET_ROUTER() view returns (address)",
  "function L1_NULLIFIER() view returns (address)",
  "function L1_NATIVE_TOKEN_VAULT() view returns (address)",
  "function CHAIN_ASSET_HANDLER() view returns (address)",
];
const TRANSFER_SELECTORS = PUH_ABI.map((s) => s.match(/function (\w+)/)![1]);

const ownable = (addr: string, runner: any) => new ethers.Contract(addr, OWNABLE2STEP_ABI, runner);
const ACCEPT_OWNERSHIP_DATA = new ethers.Interface(OWNABLE2STEP_ABI).encodeFunctionData("acceptOwnership", []);

async function discoverTargets(puh: ethers.Contract): Promise<{ name: string; address: string }[]> {
  const out: { name: string; address: string }[] = [];
  for (const fn of TRANSFER_SELECTORS) {
    try {
      const a = await puh[fn]();
      if (a && a !== ethers.ZeroAddress) out.push({ name: fn, address: ethers.getAddress(a) });
    } catch {
      /* immutable not present */
    }
  }
  return out;
}

async function main() {
  const program = new Command();
  program
    .requiredOption("--config <file>", "config JSON with l1Rpc + protocolUpgradeHandler", "governance.json")
    .option("--pk <key>", "governance-owner private key (else $GOVERNANCE_PRIVATE_KEY)")
    .option("--from <addr>", "assumed governance-owner address for planning (--dry-run, no key needed)")
    .option("--new-owner <addr>", "new owner (defaults to the config's protocolUpgradeHandler)")
    .option("--targets <list>", "comma-separated ownable target addresses (default: discover from PUH)")
    .option("--out <file>", "accept-ownership calls output", "accept-ownership.json")
    .option("--dry-run", "print the plan + write the accept file, but send no transactions", false);
  program.parse(process.argv);
  const opts = program.opts();

  const cfg = JSON.parse(fs.readFileSync(opts.config, "utf8"));
  const provider = new ethers.JsonRpcProvider(cfg.l1Rpc);
  const pk = opts.pk || process.env.GOVERNANCE_PRIVATE_KEY;
  let signer: ethers.Wallet | null = null;
  let me: string;
  if (pk) {
    signer = new ethers.Wallet(pk, provider);
    me = signer.address;
  } else if (opts.dryRun && opts.from) {
    me = ethers.getAddress(opts.from); // plan only; cannot send txs without a key
  } else {
    throw new Error("provide the governance-owner key via --pk/$GOVERNANCE_PRIVATE_KEY (or --from <addr> with --dry-run)");
  }
  const puhAddr = ethers.getAddress(cfg.protocolUpgradeHandler);
  const newOwner = ethers.getAddress(opts.newOwner || puhAddr);
  console.log(`Signer (governance owner): ${me}`);
  console.log(`New owner (PUH):           ${newOwner}\n`);

  const targets = opts.targets
    ? opts.targets.split(",").map((a: string) => ({ name: "custom", address: ethers.getAddress(a.trim()) }))
    : await discoverTargets(new ethers.Contract(puhAddr, PUH_ABI, provider));

  // Classify each target by how its ownership can be moved to the PUH.
  const directTransfers: { name: string; address: string }[] = [];
  const viaGovernance = new Map<string, { name: string; address: string }[]>(); // governance addr -> targets
  const acceptCalls: { target: string; value: string; data: string }[] = [];
  const skipped: string[] = [];

  for (const t of targets) {
    const c = ownable(t.address, provider);
    let owner: string, pending: string;
    try {
      owner = ethers.getAddress(await c.owner());
    } catch {
      skipped.push(`${t.name} ${t.address}: not Ownable (no owner())`);
      continue;
    }
    try {
      pending = ethers.getAddress(await c.pendingOwner());
    } catch {
      pending = ethers.ZeroAddress;
    }

    if (owner === newOwner) {
      console.log(`= ${t.name} ${t.address}: already owned by the PUH; skipping transfer`);
    } else if (pending === newOwner) {
      console.log(`~ ${t.name} ${t.address}: transfer to PUH already pending; only acceptance needed`);
    } else if (owner === me) {
      console.log(`→ ${t.name} ${t.address}: owned by signer (EOA); will transferOwnership(PUH)`);
      directTransfers.push(t);
    } else {
      // owner is a contract — check whether it's a Governance whose owner is the signer.
      const gov = new ethers.Contract(owner, GOVERNANCE_ABI, provider);
      let govOwner: string | null = null;
      try {
        govOwner = ethers.getAddress(await gov.owner());
      } catch {
        govOwner = null;
      }
      if (govOwner === me) {
        console.log(`⮑ ${t.name} ${t.address}: owned by Governance ${owner} (signer is its owner); will route transfer`);
        const arr = viaGovernance.get(owner) || [];
        arr.push(t);
        viaGovernance.set(owner, arr);
      } else {
        skipped.push(`${t.name} ${t.address}: owner ${owner} not controllable by signer (gov owner ${govOwner})`);
        continue;
      }
    }
    // The PUH must accept ownership of every target whose handover we (will) initiate or that is pending.
    if (owner !== newOwner) {
      acceptCalls.push({ target: t.address, value: "0", data: ACCEPT_OWNERSHIP_DATA });
    }
  }

  if (skipped.length) {
    console.log("\nSkipped (signer cannot transfer):");
    for (const s of skipped) console.log(`  ! ${s}`);
  }

  // --- Step 1: initiate transfers ---
  if (opts.dryRun) {
    console.log("\n[dry-run] no transactions sent.");
  } else {
    for (const t of directTransfers) {
      process.stdout.write(`\ntransferOwnership(${newOwner}) on ${t.name} ${t.address} ... `);
      const tx = await ownable(t.address, signer).transferOwnership(newOwner);
      await tx.wait();
      console.log(`ok (${tx.hash})`);
    }
    for (const [govAddr, ts] of viaGovernance) {
      const gov = new ethers.Contract(govAddr, GOVERNANCE_ABI, signer);
      const calls = ts.map((t) => ({
        target: t.address,
        value: 0n,
        data: ownable(t.address, provider).interface.encodeFunctionData("transferOwnership", [newOwner]),
      }));
      const operation = { calls, predecessor: ethers.ZeroHash, salt: ethers.hexlify(ethers.randomBytes(32)) };
      console.log(`\nGovernance ${govAddr}: scheduling+executing transferOwnership for ${ts.length} contract(s) ...`);
      const sd = await gov.scheduleTransparent(operation, 0);
      await sd.wait();
      console.log(`  scheduled (${sd.hash})`);
      const ex = await gov.execute(operation);
      await ex.wait();
      console.log(`  executed  (${ex.hash})`);
    }
  }

  // --- Step 2: emit acceptOwnership() calls for the PUH (sample-upgrade.json format) ---
  const proposal = {
    description: `Accept ownership of ${acceptCalls.length} ZKsync ecosystem contract(s) by the ProtocolUpgradeHandler`,
    executor: ethers.ZeroAddress,
    salt: ethers.hexlify(ethers.randomBytes(32)),
    calls: acceptCalls,
  };
  fs.writeFileSync(opts.out, JSON.stringify(proposal, null, 2));
  console.log(`\nWrote ${acceptCalls.length} acceptOwnership() call(s) to ${opts.out}`);
  console.log(`Next: cli-vote create --calls ${opts.out}  (then vote/queue/execute; the PUH accepts ownership).`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
