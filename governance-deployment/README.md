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
npm install                                # self-contained deps (ethers v6, zksync-ethers, ts-node)
export PRIVATE_KEY=0x<deployer>            # holds Sepolia ETH; will receive the ZK supply
./redeploy.sh all
```

> The CLI tools (`cli-vote`, `finalize-l1`) and the orchestrator depend only on this directory's
> `npm install` — you do **not** need to install `l2-contracts` (its hardhat deps are unrelated and
> can hit peer-dependency conflicts under modern npm). `deploy-l2.ts`/`verify-l2.js` only read the
> already-built `l2-contracts/artifacts-zk`; rebuild those with `cd l2-contracts && npm install
> --legacy-peer-deps && npm run compile` only if you need to recompile.

`redeploy.sh` is **step-based and resumable** — each step writes a marker under
`.redeploy-state/`, so if you stop it (e.g. while waiting for the L2 deposit to be credited, which
takes a few minutes) and re-run, it continues where it left off. You can also run a single step:
`./redeploy.sh bridge | l2 | l1 | assemble | verify`.

Tunables (env): `L1_RPC`, `L2_RPC`, `SAFE_OWNER` (default the production SC owner
`0xD64e136566a9E04eb05B30184fF577F52682D182`), `BRIDGE_AMOUNT`, `ZK_MINT_AMOUNT`.

## Holding & delegating the ZK token — `zk-token.ts`

The initial ZK supply was moved to the governance EOA `0xD64e136566a9E04eb05B30184fF577F52682D182`.
ERC20Votes power comes from *delegated* balance, so to be able to vote that account must delegate
(to itself). Run with **that address's key**:

```bash
cd governance-deployment && npm install
export PRIVATE_KEY=0x<key of 0xD64e…>
npx ts-node --project tsconfig.json zk-token.ts balance              # show balance / votes / delegatee
npx ts-node --project tsconfig.json zk-token.ts delegate             # self-delegate -> can now vote
# (needs a little L2 ETH on 0xD64e… to pay gas)
# transfer too, if needed:  zk-token.ts transfer --to 0x.. --all | --amount <wholeZK>
```

## Using the governance

* **Vote on L2** with `cli-vote` — see [README-cli-vote.md](./README-cli-vote.md).
* **Finalize on L1** with `finalize-l1` — the Security-Council owner approves the upgrade id and
  executes it (mirrors era-contracts' `SecurityCouncilApproveStageUpgrade.s.sol`).

## Emergency upgrade — `emergency-upgrade.ts`

Executes an **emergency** protocol upgrade through the `EmergencyUpgradeBoard` (bypasses the L2 vote
/ timelock, executes immediately) — a TS port of era-contracts'
`Utils.executeEmergencyProtocolUpgrade` (the `SecurityCouncilEmergencyStageUpgrade` script). It
requires the joint approval of **Guardians (≥5/8) + Security Council (≥9/12) + ZK Foundation**, built
as EIP-712 signatures over the upgrade id:

```bash
export GOVERNANCE_PRIVATE_KEY=0x<common Safe-owner key>
npx ts-node --project tsconfig.json emergency-upgrade.ts --config governance.json --calls upgrade.json
# inspect the signatures without sending:  ... --calls upgrade.json --dry-run
```

`upgrade.json` is the same `sample-upgrade.json` format (`calls`, `salt`). The script reads the
Guardians/SecurityCouncil member Safes and the ZK Foundation Safe, signs each Safe's
`getMessageHash` of the relevant board EIP-712 digest, and submits
`EmergencyUpgradeBoard.executeEmergencyUpgrade(...)`. Like `finalize-l1`, it assumes the member Safes
are 1-of-1 owned by the provided EOA (verify with `verify-governance.ts`). The three EIP-712 digests
were checked against the on-chain typehashes; full on-chain execution needs the real Safe-owner key.

## Verifying a deployed handler — `verify-governance.ts`

Independently checks a deployed `ProtocolUpgradeHandler`: given the PUH, the bridgehub and the L2
governor (timelock), it re-derives every constructor address by traversing the bridgehub and asserts
they match the PUH's stored immutables (`BRIDGE_HUB`, `L1_ASSET_ROUTER`, `L1_NULLIFIER`,
`L1_NATIVE_TOKEN_VAULT`, `CHAIN_ASSET_HANDLER`, plus `ZKSYNC_ERA`/`CHAIN_TYPE_MANAGER` resolved via
the era chain, and `L2_PROTOCOL_GOVERNOR`); checks the SecurityCouncil/Guardians/EmergencyUpgradeBoard
are wired back to the PUH; and confirms all 12 SC + 8 guardian member safes and the ZK Foundation safe
are 1-of-1 Gnosis Safes owned by the **same EOA**, which it prints.

```bash
npx ts-node --project tsconfig.json verify-governance.ts --config governance.json
# or fully explicit:
#   verify-governance.ts --puh 0x.. --bridgehub 0x.. --l2-gov 0x.. --l1-rpc https://..
```

## Migrating ecosystem ownership to the new handler — `governance-transfer.ts`

The ZKsync ecosystem contracts (Bridgehub, ChainTypeManager, L1AssetRouter, L1Nullifier,
L1NativeTokenVault, ChainAssetHandler — all `Ownable2Step` in era-contracts) are controlled by the
old governance (the `Governance.sol` contract and/or the governance EOA). Handing them to the new
`ProtocolUpgradeHandler` (PUH) is a two-step (`Ownable2Step`) process:

```bash
# Step 1 — current owner initiates the transfer to the PUH (direct tx for EOA-owned contracts,
#          routed through Governance.scheduleTransparent+execute for Governance-owned ones):
export GOVERNANCE_PRIVATE_KEY=0x<governance-owner>
npx ts-node --project tsconfig.json governance-transfer.ts --config governance.json
#   -> writes accept-ownership.json (the acceptOwnership() calls, sample-upgrade.json format)

# Plan only, without a key (uses the governance-owner *address* to classify + emit the accept file):
npx ts-node --project tsconfig.json governance-transfer.ts --dry-run --from 0x<governance-owner>

# Step 2 — the PUH accepts ownership: feed the generated file through cli-vote and execute it:
npx ts-node --project tsconfig.json cli-vote.ts create --calls accept-ownership.json
#   -> then vote / queue / execute (see README-cli-vote.md); the PUH runs acceptOwnership() on each.
```

It also migrates the **proxy upgrade rights**: the ecosystem contracts are transparent proxies whose
EIP-1967 admin slot points at a (governance-owned) `ProxyAdmin` — one shared ProxyAdmin in this
ecosystem (`0xE004…01d2`). The script discovers it from the proxies' admin slot and transfers it to
the PUH as well. Because OZ `ProxyAdmin` is single-step `Ownable` (no `acceptOwnership`), that
transfer completes immediately and it is **not** added to the accept-ownership file.

`governance-transfer.ts` walks the **bridgehub** to discover the ownable L1 ecosystem contracts —
Bridgehub, L1AssetRouter, L1Nullifier, L1NativeTokenVault, CTMDeploymentTracker, ChainAssetHandler,
and the **Era ChainTypeManager** (`PUH.CHAIN_TYPE_MANAGER`) with its ValidatorTimelock/RollupDAManager.
Mirroring the mainnet pre-v31 state — the ProtocolUpgradeHandler controls the ecosystem contracts and
**Era, but not ZKsync OS** — it **skips the ZKsync OS CTM** (the other CTM serving the rest of the
chains) and everything tied to it. It detects
each contract's ownership path (direct EOA vs `Governance.sol`), performs step 1, and emits step 2.
The two `RollupDAManager`s (one per CTM) have no bridgehub getter, so they are **hard-coded** in the
script for the chain-301 ecosystem (era `0x6b7D…d411`, other `0x2732…656A`), each derived + verified
from the chain's diamond AdminFacet (`diamond.getRollupDAManager()`, AdminFacet identified by
`getName()=="AdminFacet"`) — see the header comment in `governance-transfer.ts` for the exact
`cast` checks. Other contracts without a getter in your version (an unset `ValidatorTimelock`, or
`ServerNotifier` — which is owned by the per-chain ChainAdmin, not this governance) can be appended
via `"ownableTargets": ["0x…"]` in the config or `--targets 0x..,0x..`. Verified against chain-301:
it finds **9 targets** — the Era CTM (`0x3Cc8…`) + its RollupDAManager, the shared ProxyAdmin and the
core ecosystem contracts — and **skips the ZKsync OS CTM** (`0x54D5…`) and its RollupDAManager.

## Notes / gotchas

* This Era testnet **does not mine empty blocks**, so `ethers` `.wait()` (which waits for a
  *subsequent* confirmation) hangs; all tooling polls `eth_getTransactionReceipt` directly instead.
* The L2 deposit (`bridge-to-l2.ts`) uses a public Sepolia RPC for the L1 side — the Tenderly
  gateway rate-limits the many calls `deposit()` makes.
