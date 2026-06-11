# `finalize-l1` — Security-Council approval & execution on L1

`finalize-l1` is the L1 counterpart to `cli-vote`. After an L2 vote has produced an L2→L1 message,
that message must be **relayed to the `ProtocolUpgradeHandler` via `startUpgrade`** (proving its L2
inclusion) before the Security Council can approve it. `finalize-l1` does all of this end-to-end:
given the **governance EOA** that is the sole owner of every Security-Council member Safe
(`0xD64e136566a9E04eb05B30184fF577F52682D182` in this deployment), it
1. if the upgrade is not yet registered on the PUH (state `None`), fetches the L2→L1 inclusion proof
   from the L2 RPC (for the cli-vote `executeTx`) and calls `ProtocolUpgradeHandler.startUpgrade`
   (this is what moves the upgrade into `Waiting` — skipping it causes the
   *"Upgrade with this id is not waiting for the approval from Security Council"* revert);
2. produces the required member signatures and calls `SecurityCouncil.approveUpgradeSecurityCouncil`;
3. optionally calls `ProtocolUpgradeHandler.execute`.

> `startUpgrade` needs the L2 batch containing the message to be **sealed and proven on L1** (so
> `getLogProof` returns a proof). On testnet that can take a while after the L2 `execute`; until then
> the proof is `null` and you should retry later.

It is a TypeScript port of era-contracts'
[`Utils.securityCouncilApproveUpgrade`](https://github.com/matter-labs/era-contracts/blob/main/l1-contracts/deploy-scripts/SecurityCouncilApproveStageUpgrade.s.sol)
and only works when one EOA owns all the member Safes (as in this testnet redeployment).

## Usage

```bash
export GOVERNANCE_PRIVATE_KEY=0x<key of 0xD64e…>   # the SC-member-safe owner
alias finalize-l1='node_modules/.bin/ts-node --project tsconfig.json finalize-l1.ts'

# Relay (startUpgrade if needed) + approve + execute, using the cli-vote proposal file:
finalize-l1 --proposal proposals/<proposalId>.json --execute
#   (the proposal file carries the UpgradeProposal struct, the upgrade id and the L2 executeTx;
#    pass --l2-tx <hash> to override the L2 execution tx used for the proof)

# Approve only, for an already-started upgrade (id = keccak256 of the message, printed by cli-vote):
finalize-l1 --id 0xdf9f…91e3

# Inspect the signatures without sending any tx:
finalize-l1 --id 0xdf9f…91e3 --dry-run
```

Config (`governance.json`) must contain `l1Rpc`, `protocolUpgradeHandler`, `securityCouncil` — and
`l2Rpc` (for the `startUpgrade` proof). Use `--proposal` (not just `--id`) so the script has the
proposal struct + `executeTx` needed for `startUpgrade`.

## How it works (and why it is correct)

For each of the 12 SC member Safes (read in ascending order from `SecurityCouncil.members`, matching
the order `checkSignatures` expects):

1. Build the SecurityCouncil EIP-712 digest
   `digest = hashTypedData(domain={name:"SecurityCouncil",version:"1",chainId,verifyingContract:SC}, ApproveUpgradeSecurityCouncil{id})`.
2. Ask the Safe for its EIP-712 SafeMessage hash over `abi.encode(digest)`
   (`Safe.getMessageHash(abi.encode(digest))`).
3. Sign that hash with the owner EOA (raw ECDSA, `v∈{27,28}`), packed as `r‖s‖v`.

We submit `(members, signatures)` to `SecurityCouncil.approveUpgradeSecurityCouncil(id, …)`. The
council validates each signer via `signer.isValidSignatureNow(digest, sig)`; because the signer is a
Safe (a contract), this dispatches to the Safe's EIP-1271 `isValidSignature(digest, sig)`, which
internally re-derives the **same** SafeMessage hash from `digest` and recovers the owner from `sig`
— exactly the hash we signed in step 2. With ≥ `APPROVE_UPGRADE_SECURITY_COUNCIL_THRESHOLD` (6 of 12)
valid signatures, the council forwards the approval to the handler. On the testnet handler
(`UPGRADE_DELAY_PERIOD = 0`) the upgrade becomes `Ready` immediately, so `--execute` can run
`ProtocolUpgradeHandler.execute(proposal)` in the same invocation.

> Note: this tool is **not** exercised against the live deployment because the governance EOA's key
> is not available here. Its signing scheme is validated structurally (see the review above) and the
> upgrade-id / message handling shares the same `lib/upgrade.ts` encoders that the passing fork test
> uses.
