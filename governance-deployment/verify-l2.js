#!/usr/bin/env node
/**
 * verify-l2.js — verify the deployed L2 governance contracts on the ZKsync Era testnet explorer's
 * dedicated contract verifier (https://explorer-api.zksync-era-testnet.zksync.dev/contract_verification,
 * surfaced at https://explorer.zksync-era-testnet.zksync.dev). This is the standard zksync verifier
 * API: POST the standard-JSON input (as an object) + solc/zksolc versions, then poll the request id.
 *
 * Reads addresses from deployments/l2-governance.json and the solc standard-JSON input from the
 * l2-contracts hardhat build-info, recomputes each contract's constructor args, submits, and polls.
 *
 * Env: L2_VERIFIER (default the era-testnet verifier), ZKSOLC_VERSION (default v1.4.0),
 *      SOLC_VERSION (default 0.8.24).
 */
const https = require("https");
const http = require("http");
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const VERIFIER = process.env.L2_VERIFIER || "https://explorer-api.zksync-era-testnet.zksync.dev/contract_verification";
const ZKSOLC = process.env.ZKSOLC_VERSION || "v1.4.0";
const SOLC = process.env.SOLC_VERSION || "0.8.24";
const L2DIR = path.join(__dirname, "..", "l2-contracts");
const dep = JSON.parse(fs.readFileSync(path.join(__dirname, "deployments", "l2-governance.json"), "utf8"));

function loadInput() {
  const dir = path.join(L2DIR, "artifacts-zk", "build-info");
  for (const f of fs.readdirSync(dir)) {
    const bi = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
    if (bi.input?.sources?.["src/ZkProtocolGovernor.sol"]) return bi.input;
  }
  throw new Error("no build-info with ZkProtocolGovernor found; run `npm run compile` in l2-contracts");
}
const INPUT = loadInput();
const tokenAbi = require(path.join(L2DIR, "artifacts-zk/src/ZkTokenV2.sol/ZkTokenV2.json")).abi;
const enc = (types, vals) => ethers.AbiCoder.defaultAbiCoder().encode(types, vals);
const lib = VERIFIER.startsWith("https") ? https : http;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function req(method, url, body) {
  return new Promise((res, rej) => {
    const data = body ? JSON.stringify(body) : undefined;
    const r = lib.request(url, { method, headers: { "content-type": "application/json" } }, (x) => {
      let d = ""; x.on("data", (c) => (d += c)); x.on("end", () => res({ code: x.statusCode, body: d }));
    });
    r.on("error", rej);
    if (data) r.write(data);
    r.end();
  });
}

async function verify(label, address, fqn, ctorArgs) {
  process.stdout.write(`\n[${label}] ${address} (${fqn})\n`);
  const sub = await req("POST", VERIFIER, {
    contractName: fqn,
    sourceCode: INPUT,
    codeFormat: "solidity-standard-json-input",
    compilerSolcVersion: SOLC,
    compilerZksolcVersion: ZKSOLC,
    optimizationUsed: true,
    constructorArguments: ctorArgs || "0x",
    contractAddress: address,
  });
  if (/already verified/i.test(sub.body)) { console.log("  -> already verified"); return true; }
  if (sub.code >= 400) { console.log("  submit failed:", sub.code, sub.body.slice(0, 200)); return false; }
  const id = sub.body.replace(/[^0-9]/g, "");
  if (!id) { console.log("  no request id:", sub.body.slice(0, 120)); return false; }
  for (let i = 0; i < 15; i++) {
    await sleep(6000);
    const s = await req("GET", `${VERIFIER}/${id}`);
    let st; try { st = JSON.parse(s.body).status; } catch { st = s.body; }
    if (/successful/i.test(st)) { console.log("  -> successful (id", id + ")"); return true; }
    if (/failed|error/i.test(st)) { console.log("  -> FAILED:", s.body.slice(0, 200)); return false; }
  }
  console.log("  -> timed out");
  return false;
}

async function main() {
  const dpl = dep.deployer;
  const initData = new ethers.Interface(tokenAbi).encodeFunctionData("initialize", [dpl, dpl, dep.mintAmount]);
  const r = [];
  r.push(["ZkTokenV2 impl", await verify("token impl", dep.zkTokenImpl, "src/ZkTokenV2.sol:ZkTokenV2", "0x")]);
  r.push(["ProxyAdmin", await verify("proxy admin", dep.zkTokenProxyAdmin,
    "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin", "0x")]);
  r.push(["ZkToken proxy", await verify("token proxy", dep.zkToken,
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
    enc(["address", "address", "bytes"], [dep.zkTokenImpl, dep.zkTokenProxyAdmin, initData]))]);
  r.push(["TimelockController", await verify("timelock", dep.timelock,
    "@openzeppelin/contracts/governance/TimelockController.sol:TimelockController",
    enc(["uint256", "address[]", "address[]", "address"], [0, [], [], dpl]))]);
  r.push(["ZkProtocolGovernor", await verify("governor", dep.governor, "src/ZkProtocolGovernor.sol:ZkProtocolGovernor",
    enc(["string", "address", "address", "uint48", "uint32", "uint256", "uint224", "uint64"],
      ["ZkProtocolGovernor", dep.zkToken, dep.timelock, dep.votingDelay, dep.votingPeriod, 0, dep.quorum, 0]))]);
  console.log("\n=== L2 verification summary ===");
  for (const [n, ok] of r) console.log(`  ${ok ? "OK  " : "FAIL"} ${n}`);
  if (r.some(([, ok]) => !ok)) process.exit(1);
}
main().catch((e) => { console.error(e); process.exit(1); });
