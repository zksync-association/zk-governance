# `finalize-l1` — Security-Council approval & execution on L1

`finalize-l1` is the L1 counterpart to `cli-vote`. After an L2 vote has produced an L2→L1 message
and that message has been relayed to the `ProtocolUpgradeHandler` (`startUpgrade`), the Security
Council must approve the upgrade before it can be executed. `finalize-l1`, given the **governance
EOA** that is the sole owner of every Security-Council member Safe
(`0xD64e136566a9E04eb05B30184fF577F52682D182` in this deployment), produces the required member
signatures, calls `SecurityCouncil.approveUpgradeSecurityCouncil`, and optionally calls
`ProtocolUpgradeHandler.execute`.

It is a TypeScript port of era-contracts'
[`Utils.securityCouncilApproveUpgrade`](https://github.com/matter-labs/era-contracts/blob/main/l1-contracts/deploy-scripts/SecurityCouncilApproveStageUpgrade.s.sol)
and only works when one EOA owns all the member Safes (as in this testnet redeployment).

## Usage

```bash
export GOVERNANCE_PRIVATE_KEY=0x<key of 0xD64e…>   # the SC-member-safe owner
alias finalize-l1='node_modules/.bin/ts-node --project tsconfig.json finalize-l1.ts'

# Approve only (id = keccak256 of the L2->L1 message, printed by cli-vote):
finalize-l1 --id 0xdf9f…91e3

# Approve and execute, using the cli-vote proposal file (provides the UpgradeProposal struct):
finalize-l1 --proposal proposals/<proposalId>.json --execute

# Inspect the signatures without sending any tx:
finalize-l1 --id 0xdf9f…91e3 --dry-run
```

Config (`governance.json`) must contain `l1Rpc`, `protocolUpgradeHandler`, `securityCouncil`.

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
