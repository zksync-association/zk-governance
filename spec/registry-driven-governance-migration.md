# Registry-Driven Governance Self-Migration (design)

**Status: design proposal** — companion to era-contracts' registry-driven protocol upgrades
([`docs/registry-driven-upgrades.md`](https://github.com/matter-labs/era-contracts/blob/claude/musing-clarke-8b5f2c/docs/registry-driven-upgrades.md),
PR [matter-labs/era-contracts#2270](https://github.com/matter-labs/era-contracts/pull/2270)).

## Problem

era-contracts is moving every protocol upgrade payload from hand-authored governance calldata to
**data behind fixed, audited-once contracts**: write-once releases/transitions/registries with
inline `EXTCODEHASH` pins, source-checked edges, factory provenance, and on-chain derivation of
everything executable. The authority chain of that model bottoms out **here**: the domain
executors' `owner` is the `ProtocolUpgradeHandler` (PUH), and their break-glass capability is
separately governed.

This layer upgrades itself by **redeploy + ownership migration**, not proxy-impl swaps (see
`scripts/Redeploy.s.sol`): a fresh PUH implementation + proxy (CREATE3), fresh **immutable**
multisigs (Guardians, SecurityCouncil, EmergencyUpgradeBoard) with config copied from the live
PUH, and then a proposal through the OLD PUH that re-points ownership/admin of every owned
contract to the new one. That proposal is hand-authored calldata reviewed by hex-decoding — the
**last remaining hand-authored upgrade surface** in the combined system.

## Non-goal: a standing `GovernanceUpgradeExecutor`

Two reasons a permanent executor contract is the wrong instrument here:

1. **The payload is an ownership-migration set, not proxy swaps.** Only the PUH is a proxy; the
   multisigs are immutable contracts replaced wholesale. A ProxyAdmin-bound executor (the
   era-contracts `EcosystemUpgradeExecutor` shape) does not describe the migration.
2. **No new authority separation.** The PUH already executes arbitrary calls. A permanently-owned
   executor between the PUH and itself is indirection without a new invariant — the same
   reasoning that removed the generic delegatecall executor/modules from the era-contracts
   design.

## Proposal: a write-once `GovernanceMigration` object

One pinned object per succession, carrying the complete migration as data:

```solidity
struct OwnershipEdge {
    address target;            // contract whose authority moves
    bytes4 transferSelector;   // transferOwnership / setPendingAdmin / changeAdmin ...
    address expectedCurrent;   // source-checked: revert if the live owner/admin differs
    address newAuthority;      // the successor (usually the new PUH proxy)
}

struct GovernanceMigrationManifest {
    address currentHandler;            // the PUH allowed to execute this migration
    address newHandlerProxy;           // successor PUH proxy
    address newHandlerImpl;            // + inline codehash pin
    bytes32 newHandlerImplCodehash;
    address newGuardians;              // fresh immutable multisigs, each with
    bytes32 newGuardiansCodehash;      //   an inline codehash pin
    address newSecurityCouncil;
    bytes32 newSecurityCouncilCodehash;
    address newEmergencyUpgradeBoard;
    bytes32 newEmergencyUpgradeBoardCodehash;
    OwnershipEdge[] edges;             // every authority hand-off, source-checked
}
```

Properties (identical discipline to the era-contracts registry objects):

- **Factory-deployed, atomic, idempotent.** `deployOrGetMigration(manifest)` deploys + initializes
  in one transaction (no uninitialized front-runnable window); CREATE2/CREATE3 with
  `salt = keccak256(abi.encode(manifest))`, so the address is a commitment to the manifest and a
  same-manifest front-run merely does the proposer's work.
- **Write-once + `manifestHash`.** No state-mutating function after `initialize`; the 32-byte
  hash is what token-holder review and the proposal pin.
- **Inline mandatory pins.** The new PUH implementation and every new multisig carry their
  expected `EXTCODEHASH` beside the address; `validate()` reverts on drift and runs on the
  execution path.
- **Source-checked edges.** Each edge requires the live owner/admin to equal `expectedCurrent`
  before moving it — a stale or replayed migration can never re-point authority backwards. This
  is the `expectedOldImpl` property of era-contracts' `EcosystemContractRow`, applied to
  authority instead of implementations.
- **One call in one proposal.** `migration.execute()` is gated `msg.sender == currentHandler` and
  performs the PUH proxy-impl swap plus every edge. The proposal body collapses from a page of
  ownership calls to a single pinned object; the audit unit is the manifest. The
  EmergencyUpgradeBoard's existing powers are untouched — it remains the break-glass analogue.

## Coupling to era-contracts

The era-contracts executor fleet (`CTMUpgradeExecutor`, `EcosystemUpgradeExecutor`) holds
`owner` / `breakGlassGovernor` pointers that are themselves edges a governance succession must
move — i.e. rows in this object's `edges` array (two-step `transferOwnership` +
`transferBreakGlassGovernor`). The source-checked-edge row shape should therefore be a small
shared library rather than two divergent implementations.

## Sequencing

- Implementation lives in this repository (its own audit scope); nothing in
  era-contracts#2270 blocks on it.
- Suggested order: land the current audit round (PR #36) first; `GovernanceMigration` targets the
  NEXT succession — meaning the migration executed by the PUH version shipped in #36 would be the
  first registry-driven one.
