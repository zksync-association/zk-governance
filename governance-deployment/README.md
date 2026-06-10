# ZKsync governance — full testnet redeployment & tooling

This directory contains a **single reproducible redeployment** of the entire ZKsync governance
stack onto a testnet, plus CLI tooling to drive it:

| Side | Contracts |
|---|---|
| **L2** (ZKsync Era testnet, chainId 301) | `ZkToken` (ZkTokenV2 behind a transparent proxy), `TimelockController`, `ZkProtocolGovernor` |
| **L1** (Sepolia) | `TestnetProtocolUpgradeHandler` (behind a transparent proxy), `SecurityCouncil` (12), `Guardians` (8), `EmergencyUpgradeBoard`, and 21 single-owner Gnosis Safe member wallets + the ZK Foundation Safe |

The L1 `ProtocolUpgradeHandler` is wired to the L2 `TimelockController` as its
`L2_PROTOCOL_GOVERNOR`: the timelock is what executes the governor's queued calls and is therefore
the `msg.sender` of the L2→L1 upgrade message that `startUpgrade` authenticates.

The deployer/user receives a supermajority of the ZK supply (the full initial mint) and
self-delegates, so it can pass any vote on its own in a testnet setting.

## Layout

```
governance-deployment/
  redeploy.sh           # one-shot, resumable full redeployment (steps: bridge,l2,l1,assemble,verify)
  bridge-to-l2.ts       # fund the L2 deployer by bridging ETH from Sepolia
  deploy-l2.ts          # deploy the L2 token + timelock + governor (zksync-ethers)
  verify.sh             # verify deployed contracts (Sourcify on L1; best-effort on L2)
  cli-vote.ts           # manage votes: list/create/vote/status/queue/execute/message/prove
  finalize-l1.ts        # SC-owner approves + executes an upgrade on L1
  lib/                  # shared encoders (upgrade.ts) + config/doc assembler (assemble.ts)
  examples/             # sample --calls JSON
  governance.json       # generated cli config (addresses + RPCs)
  deployed-addresses.md # generated address book
l1-contracts/script/DeployL1Governance.s.sol     # Foundry L1 deploy
l1-contracts/test/L2MessageCompatForkTest.t.sol   # fork test: L2->L1 message <-> deployed PUH
```

## Reproduce the full deployment

```bash
cd governance-deployment
export PRIVATE_KEY=0x<deployer>            # holds Sepolia ETH; will receive the ZK supply
./redeploy.sh all
```

`redeploy.sh` is **step-based and resumable** — each step writes a marker under
`.redeploy-state/`, so if you stop it (e.g. while waiting for the L2 deposit to be credited, which
takes a few minutes) and re-run, it continues where it left off. You can also run a single step:
`./redeploy.sh bridge | l2 | l1 | assemble | verify`.

Tunables (env): `L1_RPC`, `L2_RPC`, `SAFE_OWNER` (default the production SC owner
`0xD64e136566a9E04eb05B30184fF577F52682D182`), `BRIDGE_AMOUNT`, `ZK_MINT_AMOUNT`.

## Using the governance

* **Vote on L2** with `cli-vote` — see [README-cli-vote.md](./README-cli-vote.md).
* **Finalize on L1** with `finalize-l1` — the Security-Council owner approves the upgrade id and
  executes it (mirrors era-contracts' `SecurityCouncilApproveStageUpgrade.s.sol`).

## Notes / gotchas

* This Era testnet **does not mine empty blocks**, so `ethers` `.wait()` (which waits for a
  *subsequent* confirmation) hangs; all tooling polls `eth_getTransactionReceipt` directly instead.
* The L2 deposit (`bridge-to-l2.ts`) uses a public Sepolia RPC for the L1 side — the Tenderly
  gateway rate-limits the many calls `deposit()` makes.
