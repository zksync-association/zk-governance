#!/usr/bin/env node
/**
 * verify-l2.js — verify the deployed L2 governance contracts on the ZKsync Era testnet block
 * explorer. The explorer exposes an Etherscan-compatible endpoint
 * (`/api?module=contract&action=verifysourcecode`) backed by the EraVM contract verifier, which
 * (unlike classic Etherscan) expects `sourceCode` to be the standard-JSON-input *object* and a
 * `zksolcVersion` field — hardhat-zksync-verify's etherscan flow sends a stringified input and
 * fails, so we submit directly here.
 *
 * Reads addresses from deployments/l2-governance.json and the solc standard-JSON input from the
 * l2-contracts hardhat build-info, recomputes each contract's constructor args, submits, and polls.
 *
 * Env: L2_EXPLORER_API (default the era-testnet explorer), ZKSOLC_VERSION (default v1.4.0).
 */
const https = require("https");
const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");

const API = process.env.L2_EXPLORER_API || "https://block-explorer-api.zksync-era-testnet.zksync.dev/api";
const ZKSOLC = process.env.ZKSOLC_VERSION || "v1.4.0";
const SOLC = "0.8.24";
const L2DIR = path.join(__dirname, "..", "l2-contracts");
const dep = JSON.parse(fs.readFileSync(path.join(__dirname, "deployments", "l2-governance.json"), "utf8"));

// Find the build-info whose standard-JSON input contains our sources.
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
const enc = (types, vals) => ethers.AbiCoder.defaultAbiCoder().encode(types, vals).slice(2);

function post(body) {
  const data = JSON.stringify(body);
  return new Promise((res, rej) => {
    const r = https.request(API, { method: "POST", headers: { "content-type": "application/json" } }, (x) => {
      let d = ""; x.on("data", (c) => (d += c)); x.on("end", () => res(d));
    });
    r.on("error", rej); r.write(data); r.end();
  });
}
const get = (u) => new Promise((res, rej) => https.get(u, (x) => { let d = ""; x.on("data", (c) => (d += c)); x.on("end", () => res(d)); }).on("error", rej));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function verify(label, address, fqn, ctorArgs) {
  process.stdout.write(`\n[${label}] ${address} (${fqn})\n`);
  const sub = await post({
    module: "contract", action: "verifysourcecode", codeFormat: "solidity-standard-json-input",
    contractname: fqn, contractaddress: address, compilerversion: SOLC, zksolcVersion: ZKSOLC,
    optimizationUsed: "1", constructorArguements: ctorArgs || "", sourceCode: INPUT,
  });
  let parsed;
  try { parsed = JSON.parse(sub); } catch { console.log("  submit failed:", sub); return false; }
  if (/already verified/i.test(parsed.result || "")) { console.log("  -> already verified"); return true; }
  if (parsed.status !== "1") { console.log("  submit:", sub); return false; }
  const guid = parsed.result;
  for (let i = 0; i < 15; i++) {
    await sleep(7000);
    const s = await get(`${API}?module=contract&action=checkverifystatus&guid=${guid}`);
    const r = (() => { try { return JSON.parse(s).result; } catch { return s; } })();
    if (/Pass|verified/i.test(r)) { console.log("  ->", r); return true; }
    if (/already/i.test(r)) { console.log("  -> already verified"); return true; }
    if (/Fail|Error/i.test(r)) { console.log("  ->", r); return false; }
  }
  console.log("  -> timed out");
  return false;
}

async function main() {
  const dpl = dep.deployer;
  const mint = dep.mintAmount;
  const initData = new ethers.Interface(tokenAbi).encodeFunctionData("initialize", [dpl, dpl, mint]);
  const results = [];
  results.push(["ZkTokenV2 impl", await verify("token impl", dep.zkTokenImpl, "src/ZkTokenV2.sol:ZkTokenV2", "")]);
  results.push(["ProxyAdmin", await verify("proxy admin", dep.zkTokenProxyAdmin,
    "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol:ProxyAdmin", "")]);
  results.push(["ZkToken proxy", await verify("token proxy", dep.zkToken,
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy",
    enc(["address", "address", "bytes"], [dep.zkTokenImpl, dep.zkTokenProxyAdmin, initData]))]);
  results.push(["TimelockController", await verify("timelock", dep.timelock,
    "@openzeppelin/contracts/governance/TimelockController.sol:TimelockController",
    enc(["uint256", "address[]", "address[]", "address"], [0, [], [], dpl]))]);
  results.push(["ZkProtocolGovernor", await verify("governor", dep.governor, "src/ZkProtocolGovernor.sol:ZkProtocolGovernor",
    enc(["string", "address", "address", "uint48", "uint32", "uint256", "uint224", "uint64"],
      ["ZkProtocolGovernor", dep.zkToken, dep.timelock, dep.votingDelay, dep.votingPeriod, 0, dep.quorum, 0]))]);
  console.log("\n=== L2 verification summary ===");
  for (const [n, ok] of results) console.log(`  ${ok ? "OK  " : "FAIL"} ${n}`);
  if (results.some(([, ok]) => !ok)) process.exit(1);
}
main().catch((e) => { console.error(e); process.exit(1); });
