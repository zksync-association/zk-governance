# `cli-vote` — managing ZKsync protocol-upgrade votes on testnet

`cli-vote` drives the **L2 `ZkProtocolGovernor`** that sits at the top of the ZKsync governance
stack. A "vote" is an OpenZeppelin `Governor` proposal whose single on-chain action sends the
encoded protocol `UpgradeProposal` as an **L2→L1 message** through the L2 `L1Messenger` system
contract (`0x…8008`). Once the proposal is executed on L2, that message can be relayed to the L1
`ProtocolUpgradeHandler` (`startUpgrade`), approved by the Security Council (`finalize-l1`) and
executed.

```
 cli-vote create ─▶ propose ─▶ vote ─▶ queue ─▶ execute ─▶ [L2→L1 message]
                                                              │
                            ProtocolUpgradeHandler.startUpgrade◀── (relayer + proof)
                                                              │
                                              finalize-l1 (SC approve + execute)
```

## Setup

The tools reuse the `l2-contracts` Node dependencies. From `governance-deployment/`:

The tooling is self-contained — install its own dependencies (do **not** install `l2-contracts`,
whose hardhat deps are unrelated to the CLI):

```bash
cd governance-deployment
npm install                       # ethers v6 + zksync-ethers + commander + ts-node (no conflicts)
export PRIVATE_KEY=0x<deployer-or-voter-key>
alias cli-vote='npx ts-node --project tsconfig.json cli-vote.ts'   # or: npm run cli-vote --
```

Connection details come from a JSON config (default `./governance.json`, written by `redeploy.sh`):

```json
{
  "l2Rpc": "https://rpc.zksync-era-testnet.zksync.dev/",
  "l1Rpc": "https://ethereum-sepolia-rpc.publicnode.com",
  "governor": "0x…",            // L2 ZkProtocolGovernor
  "timelock": "0x…",            // L2 TimelockController (== L1 L2_PROTOCOL_GOVERNOR)
  "zkToken": "0x…",
  "governorDeployBlock": 12,
  "protocolUpgradeHandler": "0x…",  // L1, for reference / prove
  "securityCouncil": "0x…"
}
```

## Commands

| Command | Purpose |
|---|---|
| `cli-vote list` | List proposals found on-chain (+ any in the local store) with their state |
| `cli-vote create --calls <file> [--description <text>]` | Create a vote from a JSON file describing the **L1 calls** to perform |
| `cli-vote vote --proposal <id> [--support for\|against\|abstain]` | Cast a vote |
| `cli-vote status --proposal <id>` | Show governor state, tallies, quorum and the L2→L1 message |
| `cli-vote queue --proposal <id>` | Queue a `Succeeded` proposal into the timelock |
| `cli-vote execute --proposal <id>` | Execute a `Queued` proposal — **emits the L2→L1 message** |
| `cli-vote message --proposal <id>` | Print & verify the emitted L2→L1 upgrade message |
| `cli-vote prove --proposal <id>` | Fetch the L1 inclusion-proof params for `startUpgrade` (after batch seal) |

### The `--calls` JSON

Describes the actions the L1 `ProtocolUpgradeHandler` will execute (`UpgradeProposal.calls`).
`cli-vote` wraps them into an `UpgradeProposal{calls, executor, salt}`, ABI-encodes it, and proposes
a single L2 action: `L1Messenger.sendToL1(abi.encode(proposal))`.

```json
{
  "description": "Example protocol upgrade",
  "executor": "0x0000000000000000000000000000000000000000",
  "salt": "0x0000000000000000000000000000000000000000000000000000000000000001",
  "calls": [
    { "target": "0xTargetContract", "value": "0", "data": "0xabcdef…" }
  ]
}
```

* `executor` — who may call `execute` on L1 (`0x0` = anyone). Must not be the Emergency Upgrade Board.
* `salt` — disambiguates otherwise-identical proposals.
* The L1 **upgrade id** is `keccak256(abi.encode(proposal))`; `finalize-l1` consumes it.

## End-to-end example

```bash
export PRIVATE_KEY=0x<deployer>      # holds the supermajority ZK + self-delegated

# 1. Create the vote from the sample calls.
cli-vote create --calls examples/sample-upgrade.json --description "demo upgrade"
#   -> proposalId 0x…   upgradeId 0x…

# 2. Wait votingDelay (60s), then vote For.
cli-vote vote --proposal <proposalId> --support for

# 3. After votingPeriod (600s) the proposal is Succeeded; queue then execute.
cli-vote status  --proposal <proposalId>     # -> Succeeded
cli-vote queue   --proposal <proposalId>
cli-vote execute --proposal <proposalId>     # emits the L2->L1 message

# 4. Inspect / verify the emitted L2->L1 message (sender == L2 timelock).
cli-vote message --proposal <proposalId>
#   Emitted message sender: 0x<timelock>
#   Matches locally-encoded UpgradeProposal: true
#   Upgrade id (keccak256 of message): 0x…

# 5. (after the L2 batch is sealed on L1) produce the inclusion proof and relay to L1:
cli-vote prove --proposal <proposalId>       # -> {l2BatchNumber, l2MessageIndex, ...}
#   feed these into ProtocolUpgradeHandler.startUpgrade(...)
```

The real output of this exact flow against the live deployment is recorded in
[`E2E-RESULT.md`](./E2E-RESULT.md), and the message's compatibility with the deployed
`TestnetProtocolUpgradeHandler` is asserted by the Foundry fork test
`l1-contracts/test/L2MessageCompatForkTest.t.sol`.
