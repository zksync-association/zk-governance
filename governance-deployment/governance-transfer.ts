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
 * Complete set of ownable L1 ecosystem contracts (from era-contracts deploy-scripts
 * DeployL1CoreContracts.s.sol + DeployCTM.s.sol — note DeployCTM runs once *per CTM*):
 *
 *   Owned by Governance (auto-discovered from the bridgehub):
 *     - Bridgehub                bridgehub
 *     - L1AssetRouter            bridgehub.assetRouter()
 *     - L1Nullifier              assetRouter.L1_NULLIFIER()
 *     - CTMDeploymentTracker     bridgehub.l1CtmDeployer()
 *     - ChainAssetHandler        bridgehub.chainAssetHandler()
 *     - ChainTypeManager (Era)   the handler's CHAIN_TYPE_MANAGER only. The ecosystem has >1 CTM (the
 *                                Era/EraVM CTM the governance lives on, plus the ZKsync OS CTM serving
 *                                the other chains). Mirroring the mainnet pre-v31 state — the
 *                                ProtocolUpgradeHandler controls the ecosystem contracts and Era, but
 *                                NOT ZKsync OS — we migrate ONLY the Era CTM and skip the ZKsync OS CTM
 *                                and everything tied to it.
 *     - RollupDAManager (Era)    the Era CTM's RollupDAManager only (the ZKsync OS one is skipped)
 *   Owned by the governance EOA (config.ownerAddress) — auto-discovered, transferred directly:
 *     - L1NativeTokenVault       assetRouter.nativeTokenVault()
 *     - ValidatorTimelock × N    ctm.validatorTimelock() when set, else config.ownableTargets
 *   Owned by the per-chain ChainAdmin (NOT this governance):
 *     - ServerNotifier    × N    — only migrate if your deployment points it here; pass via config
 *   Proxy upgrade rights (separate from owner()): the ecosystem contracts are
 *     TransparentUpgradeableProxies; their EIP-1967 admin slot holds a (governance-owned) ProxyAdmin
 *     — usually ONE shared ProxyAdmin for the whole ecosystem. We discover it from the proxies' admin
 *     slot and migrate it too. NB: OZ ProxyAdmin is single-step `Ownable` (no acceptOwnership), so its
 *     transferOwnership(PUH) completes immediately and it gets NO entry in the accept-ownership file.
 *   Not Ownable (skipped): MessageRoot (owned by the bridgehub itself); chain diamonds use the
 *   Admin facet (setPendingAdmin/acceptAdmin), not Ownable — out of scope for this script.
 *
 * Discovery walks the bridgehub so every CTM (and its ValidatorTimelock) is included; contracts
 * without an on-chain getter in your version can be appended via `config.ownableTargets` or `--targets`.
 *
 * Usage:
 *   governance-transfer.ts --config governance.json --pk 0x<governance-owner> \
 *       [--new-owner 0x<PUH>] [--out accept-ownership.json] [--targets 0x..,0x..] [--dry-run]
 *
 *   # Instead of broadcasting, dump the step-1 EOA txs to a JSON file (no key needed with --from):
 *   governance-transfer.ts --config governance.json --from 0x<gov-owner> \
 *       --dump-eoa-txs eoa-txs.json [--mint 5] [--network sepolia]
 *   # …then replay that file (one tx at a time) with the key:
 *   governance-transfer.ts --pk 0x<gov-owner> --execute-dump eoa-txs.json
 *
 * Dump entries are { network, from, to, data, value:"0", valueToMint }. `valueToMint` (default 0,
 * --mint) is for harnesses that provision the sender before each tx; --execute-dump does not mint.
 *
 *   # Also emit the step-2 acceptOwnership calls in that same EOA/simulator format (from = the PUH):
 *   governance-transfer.ts --config governance.json --from 0x<gov-owner> --txs-simulator accept-txs.json
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
const PUH_ABI = [
  "function BRIDGE_HUB() view returns (address)",
  "function CHAIN_TYPE_MANAGER() view returns (address)", // the Era CTM the handler governs
];
// Bridgehub is the root of the ecosystem; all ownable contracts are reachable from it.
const BRIDGEHUB_ABI = [
  "function assetRouter() view returns (address)",
  "function l1CtmDeployer() view returns (address)", // -> CTMDeploymentTracker
  "function chainAssetHandler() view returns (address)",
  "function messageRoot() view returns (address)",
  "function getAllZKChainChainIDs() view returns (uint256[])",
  "function chainTypeManager(uint256 chainId) view returns (address)",
];
const ASSET_ROUTER_ABI = [
  "function L1_NULLIFIER() view returns (address)",
  "function nativeTokenVault() view returns (address)",
];
const CTM_ABI = ["function validatorTimelock() view returns (address)"];

const ownable = (addr: string, runner: any) => new ethers.Contract(addr, OWNABLE2STEP_ABI, runner);
const ACCEPT_OWNERSHIP_DATA = new ethers.Interface(OWNABLE2STEP_ABI).encodeFunctionData("acceptOwnership", []);

/**
 * RollupDAManager (one per CTM) is governance-owned but has no getter on the bridgehub, so it is
 * hard-coded here for the chain-301 ecosystem. How these were derived & how to re-verify:
 *   1. Take any chain of the CTM and read its diamond: `bridgehub.getZKChain(chainId)`
 *        era   CTM 0x3Cc8…18864: chain 301   -> diamond 0xD3bc4353957bc0F138318384aa207C708A9455C4
 *        zksync os CTM 0x54D5…1eb5 (ZKsync OS) : chain 36900 -> diamond 0xa837Ea7C274C2C65650eb2F3c44f5459A83148ce
 *   2. Find the AdminFacet: for fa in `diamond.facetAddresses()`, the one with `fa.getName()=="AdminFacet"`
 *        era: 0x69A6fc70d24C3A475f7B5f931121D506C7624055   zksync os: 0x68Ab53D3bf41562D02c9029b04D54C29007BcAC7
 *   3. RollupDAManager = `adminFacet.getRollupDAManager()` (equivalently `diamond.getRollupDAManager()`),
 *      which returns the `RollupDAManager` immutable set in the AdminFacet constructor
 *      `constructor(uint256 _l1ChainId, RollupDAManager _rollupDAManager)`.
 * Verify: `cast call <diamond> 'getRollupDAManager()(address)'` should equal the value below, and
 * `cast call <rollupDAManager> 'owner()(address)'` should be the Governance (0xcf96…) or its EOA owner.
 * For a different ecosystem, supply your own values via `config.ownableTargets` / `--targets` instead.
 */
const KNOWN_ROLLUP_DA_MANAGERS: { name: string; address: string; ctm: string }[] = [
  { name: "RollupDAManager(era CTM)", address: "0x6b7D8FD12eF94485c8E928a055124F94C2B5d411", ctm: "0x3Cc81628a14C824057a97C1B4Ab17758E5D18864" },
  { name: "RollupDAManager(zksync os CTM)", address: "0x2732eA4Db32527690A680D5A2B7FFae812bB656A", ctm: "0x54D55e74De9c6003E7a68a1fE70E633f05761eb5" },
];

/**
 * Discover every ownable L1 ecosystem contract, walking the bridgehub. This covers the full set
 * whose ownership era-contracts hands to governance (see DeployL1CoreContracts.s.sol / DeployCTM.s.sol):
 *   Bridgehub, L1AssetRouter, L1Nullifier, L1NativeTokenVault, CTMDeploymentTracker, ChainAssetHandler,
 *   and — crucially — EVERY ChainTypeManager (the ecosystem has more than one: the "era" CTM of the
 *   chain governance lives on, plus the CTM(s) of the other chains), each with its ValidatorTimelock.
 * Per-CTM contracts that aren't exposed via on-chain getters in every version (ValidatorTimelock when
 * unset, RollupDAManager, ServerNotifier) can be appended via `config.ownableTargets` / `--targets`.
 */
async function discoverTargets(
  provider: ethers.Provider,
  bridgehubAddr: string,
  eraCtm: string
): Promise<{ name: string; address: string }[]> {
  const out: { name: string; address: string }[] = [];
  const seen = new Set<string>();
  const add = (name: string, a?: string) => {
    if (a && a !== ethers.ZeroAddress && !seen.has(a.toLowerCase())) {
      seen.add(a.toLowerCase());
      out.push({ name, address: ethers.getAddress(a) });
    }
  };
  const tryGet = async (fn: () => Promise<string>) => { try { return await fn(); } catch { return undefined; } };

  const bh = new ethers.Contract(bridgehubAddr, BRIDGEHUB_ABI, provider);
  add("Bridgehub", bridgehubAddr);
  const ar = await tryGet(() => bh.assetRouter());
  add("L1AssetRouter", ar);
  add("CTMDeploymentTracker", await tryGet(() => bh.l1CtmDeployer()));
  add("ChainAssetHandler", await tryGet(() => bh.chainAssetHandler()));
  if (ar && ar !== ethers.ZeroAddress) {
    const arc = new ethers.Contract(ar, ASSET_ROUTER_ABI, provider);
    add("L1Nullifier", await tryGet(() => arc.L1_NULLIFIER()));
    add("L1NativeTokenVault", await tryGet(() => arc.nativeTokenVault()));
  }
  // ChainTypeManagers: the ecosystem has more than one CTM (the Era / EraVM CTM that the chain
  // governance lives on, plus the ZKsync OS CTM serving the other chains). Mirroring the mainnet
  // pre-v31 state — where the ProtocolUpgradeHandler controls the ecosystem contracts and Era, but
  // NOT ZKsync OS — we ONLY migrate the Era CTM (the handler's CHAIN_TYPE_MANAGER) and skip every
  // other CTM and anything tied to it (its ValidatorTimelock, RollupDAManager, …).
  let chains: bigint[] = [];
  try { chains = await bh.getAllZKChainChainIDs(); } catch { /* older bridgehub */ }
  const ctms = new Set<string>();
  for (const id of chains) {
    const c = await tryGet(() => bh.chainTypeManager(id));
    if (c && c !== ethers.ZeroAddress) ctms.add(ethers.getAddress(c));
  }
  for (const ctm of ctms) {
    if (ctm.toLowerCase() !== eraCtm.toLowerCase()) {
      console.log(`  (skipping non-Era CTM ${ctm} and its contracts — not governed by this handler)`);
      continue;
    }
    add("ChainTypeManager(era)", ctm);
    add("ValidatorTimelock(era)", await tryGet(() => new ethers.Contract(ctm, CTM_ABI, provider).validatorTimelock()));
  }
  // ProxyAdmin(s): the ecosystem contracts are TransparentUpgradeableProxies; their *upgrade* rights
  // live in the EIP-1967 admin slot (a ProxyAdmin, itself Ownable and governance-owned), separate
  // from the contract's own owner(). Collect the unique ProxyAdmins so their ownership migrates too.
  const ADMIN_SLOT = "0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103";
  const proxies = [...out];
  for (const t of proxies) {
    const raw = await tryGet(() => provider.getStorage(t.address, ADMIN_SLOT) as Promise<string>);
    if (!raw) continue;
    const admin = ethers.getAddress("0x" + raw.slice(-40));
    if (admin === ethers.ZeroAddress || seen.has(admin.toLowerCase())) continue;
    if ((await provider.getCode(admin)) !== "0x") add("ProxyAdmin", admin); // upgrade rights
  }
  return out;
}

/** Replay a dumped EOA-tx file: send each {to, data, value} from the signer, one at a time. */
async function executeDump(signer: ethers.Wallet, file: string): Promise<void> {
  const txs = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(txs)) throw new Error("dump file must be a JSON array of txs");
  console.log(`Executing ${txs.length} tx(s) from ${signer.address} ...`);
  for (let i = 0; i < txs.length; i++) {
    const t = txs[i];
    if (t.from && t.from.toLowerCase() !== signer.address.toLowerCase()) {
      console.warn(`  [${i}] WARNING: dump 'from' ${t.from} != signer ${signer.address}`);
    }
    if (t.valueToMint && BigInt(t.valueToMint) > 0n) {
      console.log(`  [${i}] note: valueToMint=${t.valueToMint} (provision to the sender externally; not minted here)`);
    }
    process.stdout.write(`  [${i}] -> ${t.to} data=${(t.data || "0x").slice(0, 10)}… `);
    const tx = await signer.sendTransaction({
      to: ethers.getAddress(t.to),
      data: t.data || "0x",
      value: t.value ? BigInt(t.value) : 0n,
    });
    await tx.wait();
    console.log(`ok (${tx.hash})`);
  }
  console.log("All txs executed.");
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
    .option("--dump-eoa-txs <file>", "write the step-1 EOA txs to a JSON file instead of broadcasting")
    .option("--txs-simulator <file>", "also write the step-2 acceptOwnership txs in the EOA tx format (from = PUH)")
    .option("--execute-dump <file>", "ONLY execute the txs in a previously dumped JSON file, one by one")
    .option("--mint <value>", "valueToMint field written into dumped txs", "0")
    .option("--network <name>", "network field written into dumped txs", "sepolia")
    .option("--dry-run", "print the plan + write the accept file, but send no transactions", false);
  program.parse(process.argv);
  const opts = program.opts();

  const cfg = JSON.parse(fs.readFileSync(opts.config, "utf8"));
  const provider = new ethers.JsonRpcProvider(cfg.l1Rpc);
  const pk = opts.pk || process.env.GOVERNANCE_PRIVATE_KEY;

  // --execute-dump: independent mode — just replay a dumped EOA-tx file, one tx at a time.
  if (opts.executeDump) {
    if (!pk) throw new Error("--execute-dump needs the sender key via --pk/$GOVERNANCE_PRIVATE_KEY");
    await executeDump(new ethers.Wallet(pk, provider), opts.executeDump);
    return;
  }

  const planningOnly = !pk && (opts.dryRun || opts.dumpEoaTxs) && opts.from;
  let signer: ethers.Wallet | null = null;
  let me: string;
  if (pk) {
    signer = new ethers.Wallet(pk, provider);
    me = signer.address;
  } else if (planningOnly) {
    me = ethers.getAddress(opts.from); // plan/dump only; cannot send txs without a key
  } else {
    throw new Error("provide the governance-owner key via --pk/$GOVERNANCE_PRIVATE_KEY (or --from <addr> with --dry-run/--dump-eoa-txs)");
  }
  const puhAddr = ethers.getAddress(cfg.protocolUpgradeHandler);
  const newOwner = ethers.getAddress(opts.newOwner || puhAddr);
  console.log(`Signer (governance owner): ${me}`);
  console.log(`New owner (PUH):           ${newOwner}\n`);

  // Resolve targets: auto-discover the whole ecosystem from the bridgehub, then append any extras
  // from config.ownableTargets / --targets (e.g. RollupDAManager, ServerNotifier, an unset
  // ValidatorTimelock — contracts without an on-chain getter in this version).
  let targets: { name: string; address: string }[];
  if (opts.targets) {
    targets = opts.targets.split(",").map((a: string) => ({ name: "custom", address: ethers.getAddress(a.trim()) }));
  } else {
    const puhRO = new ethers.Contract(puhAddr, PUH_ABI, provider);
    const bridgehub = ethers.getAddress(cfg.bridgehub || (await puhRO.BRIDGE_HUB()));
    const eraCtm = ethers.getAddress(await puhRO.CHAIN_TYPE_MANAGER());
    console.log(`Bridgehub:                 ${bridgehub}`);
    console.log(`Era CTM (governed):        ${eraCtm}`);
    targets = await discoverTargets(provider, bridgehub, eraCtm);
    const seen = new Set(targets.map((t) => t.address.toLowerCase()));
    const extras = [
      // Only the Era CTM's RollupDAManager (skip the ZKsync OS CTM's — see pre-v31 note above).
      ...KNOWN_ROLLUP_DA_MANAGERS.filter((r) => r.ctm.toLowerCase() === eraCtm.toLowerCase()),
      ...(((cfg.ownableTargets as string[] | undefined) || []).map((a) => ({ name: "config", address: a }))),
    ];
    for (const e of extras) {
      const addr = ethers.getAddress(e.address);
      if (!seen.has(addr.toLowerCase())) {
        seen.add(addr.toLowerCase());
        targets.push({ name: e.name, address: addr });
      }
    }
  }
  console.log(`Discovered ${targets.length} ownable target(s).\n`);

  // Classify each target by how its ownership can be moved to the PUH.
  const directTransfers: { name: string; address: string }[] = [];
  const viaGovernance = new Map<string, { name: string; address: string }[]>(); // governance addr -> targets
  const acceptCalls: { name: string; target: string; value: string; data: string }[] = [];
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
    // Ownable2Step exposes pendingOwner()/acceptOwnership(); plain Ownable (e.g. OZ ProxyAdmin)
    // does not — its transferOwnership is single-step, so it needs NO accept call.
    let twoStep = true;
    try {
      pending = ethers.getAddress(await c.pendingOwner());
    } catch {
      pending = ethers.ZeroAddress;
      twoStep = false;
    }
    const kind = twoStep ? "" : " [1-step Ownable]";

    if (owner === newOwner) {
      console.log(`= ${t.name} ${t.address}: already owned by the PUH; skipping transfer`);
    } else if (twoStep && pending === newOwner) {
      console.log(`~ ${t.name} ${t.address}: transfer to PUH already pending; only acceptance needed`);
    } else if (owner === me) {
      console.log(`→ ${t.name} ${t.address}${kind}: owned by signer (EOA); will transferOwnership(PUH)`);
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
        console.log(`⮑ ${t.name} ${t.address}${kind}: owned by Governance ${owner} (signer is its owner); will route transfer`);
        const arr = viaGovernance.get(owner) || [];
        arr.push(t);
        viaGovernance.set(owner, arr);
      } else {
        skipped.push(`${t.name} ${t.address}: owner ${owner} not controllable by signer (gov owner ${govOwner})`);
        continue;
      }
    }
    // Two-step (Ownable2Step) targets need the PUH to acceptOwnership(); one-step Ownable (ProxyAdmin)
    // transfers immediately, so no accept call is emitted for them.
    if (owner !== newOwner && twoStep) {
      acceptCalls.push({ name: t.name, target: t.address, value: "0", data: ACCEPT_OWNERSHIP_DATA });
    }
  }

  if (skipped.length) {
    console.log("\nSkipped (signer cannot transfer):");
    for (const s of skipped) console.log(`  ! ${s}`);
  }

  // --- Step 1: build the EOA transactions the governance owner must send ---
  const ownableIface = new ethers.Interface(OWNABLE2STEP_ABI);
  const govIface = new ethers.Interface(GOVERNANCE_ABI);
  const plan: { label: string; to: string; data: string }[] = [];
  for (const t of directTransfers) {
    plan.push({
      label: `Transfer ownership of ${t.name} (${t.address}) to the PUH`,
      to: t.address,
      data: ownableIface.encodeFunctionData("transferOwnership", [newOwner]),
    });
  }
  for (const [govAddr, ts] of viaGovernance) {
    const names = ts.map((t) => `${t.name} (${t.address})`).join(", ");
    const calls = ts.map((t) => ({
      target: t.address,
      value: 0n,
      data: ownableIface.encodeFunctionData("transferOwnership", [newOwner]),
    }));
    const operation = { calls, predecessor: ethers.ZeroHash, salt: ethers.hexlify(ethers.randomBytes(32)) };
    plan.push({
      label: `Governance ${govAddr}: scheduleTransparent — transfer ownership of [${names}] to the PUH`,
      to: govAddr,
      data: govIface.encodeFunctionData("scheduleTransparent", [operation, 0]),
    });
    plan.push({
      label: `Governance ${govAddr}: execute — transfer ownership of [${names}] to the PUH`,
      to: govAddr,
      data: govIface.encodeFunctionData("execute", [operation]),
    });
  }

  if (opts.dumpEoaTxs) {
    const dump = plan.map((p) => ({
      description: p.label,
      network: opts.network,
      from: me,
      to: p.to,
      data: p.data,
      value: "0",
      valueToMint: String(opts.mint),
    }));
    fs.writeFileSync(opts.dumpEoaTxs, JSON.stringify(dump, null, 2));
    console.log(`\nWrote ${dump.length} EOA tx(s) to ${opts.dumpEoaTxs}`);
    plan.forEach((p, i) => console.log(`  [${i}] ${p.label}`));
    console.log(`Execute later with:  governance-transfer.ts --config ${opts.config} --pk <key> --execute-dump ${opts.dumpEoaTxs}`);
  } else if (opts.dryRun) {
    console.log(`\n[dry-run] no transactions sent. Step-1 plan (${plan.length} tx):`);
    plan.forEach((p, i) => console.log(`  [${i}] ${p.label}`));
  } else {
    for (const p of plan) {
      process.stdout.write(`\n${p.label} ... `);
      const tx = await signer!.sendTransaction({ to: p.to, data: p.data });
      await tx.wait();
      console.log(`ok (${tx.hash})`);
    }
  }

  // --- Step 2: emit acceptOwnership() calls for the PUH (sample-upgrade.json format) ---
  const proposal = {
    description: `Accept ownership of ${acceptCalls.length} ZKsync ecosystem contract(s) by the ProtocolUpgradeHandler`,
    executor: ethers.ZeroAddress,
    salt: ethers.hexlify(ethers.randomBytes(32)),
    calls: acceptCalls.map((c) => ({
      description: `Accept ownership of ${c.name} (${c.target}) by the PUH`,
      target: c.target,
      value: c.value,
      data: c.data,
    })),
  };
  fs.writeFileSync(opts.out, JSON.stringify(proposal, null, 2));
  console.log(`\nWrote ${acceptCalls.length} acceptOwnership() call(s) to ${opts.out}`);
  console.log(`Next: cli-vote create --calls ${opts.out}  (then vote/queue/execute; the PUH accepts ownership).`);

  // Optionally also emit the step-2 acceptOwnership calls in the EOA tx format (from = the PUH,
  // which is the account that must call acceptOwnership) for a transaction simulator.
  if (opts.txsSimulator) {
    const simTxs = acceptCalls.map((c) => ({
      description: `Accept ownership of ${c.name} (${c.target}) by the PUH`,
      network: opts.network,
      from: newOwner, // the PUH executes acceptOwnership as the pending owner
      to: c.target,
      data: c.data,
      value: "0",
      valueToMint: String(opts.mint),
    }));
    fs.writeFileSync(opts.txsSimulator, JSON.stringify(simTxs, null, 2));
    console.log(`Wrote ${simTxs.length} acceptOwnership tx(s) (EOA/simulator format, from=PUH) to ${opts.txsSimulator}`);
  }
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
