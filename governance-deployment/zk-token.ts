#!/usr/bin/env ts-node
/**
 * zk-token — manage the L2 ZK governance token: check balances, transfer, and (self-)delegate.
 *
 * Voting power in ZkProtocolGovernor comes from ERC20Votes *delegated* balance, so after receiving
 * tokens an account must delegate (to itself) before it can vote.
 *
 * Connection (l2Rpc, zkToken) comes from the config (default ./governance.json); the signing key
 * from $PRIVATE_KEY or --pk.
 *
 * Commands:
 *   balance [--addr 0x..]                 show ZK balance, current votes and delegatee
 *   transfer --to 0x.. (--all | --amount <wholeZK>)   transfer ZK
 *   delegate [--to 0x..]                  delegate voting power (default: self) — run with YOUR key
 */
import { Command } from "commander";
import { Provider, Wallet, Contract } from "zksync-ethers";
import { ethers } from "ethers";
import * as fs from "fs";
import { confirmResponse } from "./lib/zkwait";

const TOKEN_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function delegate(address delegatee)",
];

function loadCfg(file: string) {
  const c = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!c.l2Rpc || !c.zkToken) throw new Error("config must include l2Rpc and zkToken");
  return c;
}
function getWallet(cfg: any, opts: any) {
  const pk = opts.pk || process.env.PRIVATE_KEY;
  if (!pk) throw new Error("provide a key via $PRIVATE_KEY or --pk");
  return new Wallet(pk, new Provider(cfg.l2Rpc));
}

async function showBalance(token: Contract, addr: string) {
  const [bal, votes, del, sym] = await Promise.all([
    token.balanceOf(addr), token.getVotes(addr), token.delegates(addr), token.symbol(),
  ]);
  console.log(`  ${addr}`);
  console.log(`    balance:   ${ethers.formatEther(bal)} ${sym}`);
  console.log(`    votes:     ${ethers.formatEther(votes)} ${sym}`);
  console.log(`    delegatee: ${del === ethers.ZeroAddress ? "(none — cannot vote until delegated)" : del}`);
}

async function main() {
  const program = new Command();
  program.option("-c, --config <file>", "config JSON", "governance.json").option("--pk <key>", "signer key (else $PRIVATE_KEY)");

  program
    .command("balance")
    .option("--addr <addr>", "address to inspect (default: signer)")
    .action(async (o, cmd) => {
      const opts = { ...program.opts(), ...o };
      const cfg = loadCfg(opts.config);
      const provider = new Provider(cfg.l2Rpc);
      const addr = opts.addr ? ethers.getAddress(opts.addr) : getWallet(cfg, opts).address;
      await showBalance(new Contract(cfg.zkToken, TOKEN_ABI, provider), addr);
    });

  program
    .command("transfer")
    .requiredOption("--to <addr>", "recipient")
    .option("--amount <wholeZK>", "amount in whole ZK")
    .option("--all", "transfer the entire balance", false)
    .action(async (o, cmd) => {
      const opts = { ...program.opts(), ...o };
      const cfg = loadCfg(opts.config);
      const wallet = getWallet(cfg, opts);
      const provider = wallet.provider as Provider;
      const token = new Contract(cfg.zkToken, TOKEN_ABI, wallet);
      const to = ethers.getAddress(opts.to);
      const bal: bigint = await token.balanceOf(wallet.address);
      const amount = opts.all ? bal : ethers.parseEther(String(opts.amount ?? "0"));
      if (amount <= 0n) throw new Error("specify --all or --amount <wholeZK>");
      if (amount > bal) throw new Error(`amount ${ethers.formatEther(amount)} exceeds balance ${ethers.formatEther(bal)}`);
      console.log(`Transferring ${ethers.formatEther(amount)} ZK ${wallet.address} -> ${to} ...`);
      const tx = await token.transfer(to, amount);
      console.log("  tx:", tx.hash);
      await confirmResponse(provider, tx, "transfer");
      console.log("Done.\nRecipient now:");
      await showBalance(new Contract(cfg.zkToken, TOKEN_ABI, provider), to);
      console.log("(The recipient must `delegate` before its balance counts as voting power.)");
    });

  program
    .command("delegate")
    .option("--to <addr>", "delegatee (default: self)")
    .action(async (o, cmd) => {
      const opts = { ...program.opts(), ...o };
      const cfg = loadCfg(opts.config);
      const wallet = getWallet(cfg, opts);
      const provider = wallet.provider as Provider;
      const token = new Contract(cfg.zkToken, TOKEN_ABI, wallet);
      const to = opts.to ? ethers.getAddress(opts.to) : wallet.address;
      console.log(`Delegating ${wallet.address}'s voting power -> ${to} ...`);
      const tx = await token.delegate(to);
      console.log("  tx:", tx.hash);
      await confirmResponse(provider, tx, "delegate");
      console.log("Done.");
      await showBalance(new Contract(cfg.zkToken, TOKEN_ABI, provider), wallet.address);
    });

  await program.parseAsync(process.argv);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
