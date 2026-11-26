## Env vars required for re-deployment

The below are the values required to re-deploy the **current** version given a deployment of the **previous** version [b1d1bdce1def3c036c06e449787a3763bf47e766](https://github.com/zksync-association/zk-governance/tree/b1d1bdce1def3c036c06e449787a3763bf47e766)).
The Security Council members are copied from the current Security Council, which must have exactly 8 members (`SecurityCouncil` requires 8).

`MainnetRedeploy.s.sol`
```bash
PRIVATE_KEY= # Deployer
CREATE3_FACTORY=0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf
L2_PROTOCOL_GOVERNOR=0x085b8B6407f150D62adB1EF926F7f304600ec714
ZKSYNC_OS_CHAIN_TYPE_MANAGER=
PUH_PROXY_MAINNET=0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3 
ERA_CHAIN_ID=324
```

`TestnetRedeploy.s.sol` (deploys `TestnetProtocolUpgradeHandler`). The values are Stage's (Sepolia, Era chain 270), the
handler `StageRemoveGuardians.s.sol` targets too. The Era Sepolia testnet's handler `0x9B956d24…` can't be used: it isn't
a proxy, predates the getters the script reads (it reverts at `CHAIN_TYPE_MANAGER()`) and no longer owns the testnet
Bridgehub.
```bash
PRIVATE_KEY= # Deployer
CREATE3_FACTORY=0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf
L2_PROTOCOL_GOVERNOR=0x504d39a2DE2ff99A2Da8D95e6ef811Bd9b107968
ZKSYNC_OS_CHAIN_TYPE_MANAGER=0x73Bee414c6e006525F3CcEedf6d8004C0370502e
PUH_PROXY_TESTNET=0x8f08627524aeD610192132A425D6b9C32a1727EF
ERA_CHAIN_ID=270
```
## Guardians removal

`MainnetRemoveGuardians.s.sol` / `StageRemoveGuardians.s.sol` deploy (via CREATE2) the new
`ProtocolUpgradeHandler` implementation (the role previously held by the Guardians belongs to the
ZK Foundation), the two-party `EmergencyUpgradeBoard` (Security Council + ZK Foundation) and the
`ProtocolUpgradeHandlerStateCheck` helper, and print the `Call[]` of the protocol upgrade (ZIP) that
removes the Guardians from L1:

1. `ProtocolUpgradeHandlerStateCheck.checkRoles(...)`: reverts unless the handler still holds the
   Security Council and Emergency Upgrade Board the proposal was built against (the ones installed by
   v31). v31 re-initializes the handler, so the removal must only execute after it; a reverted
   execution can be retried later.
2. `ProxyAdmin.upgradeAndCall(handler, newImplementation, "")`: no re-initialization, the proxy is
   already initialized by v31 at the version of `initialize`.
3. `ProtocolUpgradeHandler.updateZkFoundation(zkFoundationSafe)`: the legal veto extension and the
   upgrade approval move to the ZK Foundation Safe of the current board.
4. `ProtocolUpgradeHandler.updateEmergencyUpgradeBoard(newBoard)`.

The only input is the handler proxy. The proxy admin, the implementation whose immutables are copied,
the roles and the ZK Foundation Safe are read from it, so the script runs once v31 is executed and
reverts before (and after the removal). Stage uses `TestnetProtocolUpgradeHandler`, like v31 does.

```bash
CREATE2_FACTORY= # Optional, defaults to 0x4e59b44847b379578588920cA78FbF26c0B4956C
CREATE2_SALT= # Optional, defaults to bytes32(0)
DEPLOY_OUTPUT_TOML= # Optional, e.g. ./script-out/remove-guardians.toml
forge script scripts/MainnetRemoveGuardians.s.sol:MainnetRemoveGuardians --rpc-url $MAINNET_RPC --broadcast <signer>
```

The fork test replays the v31 handler upgrade, runs the script against it and passes the generated
proposal through the `ProtocolUpgradeHandler` state machine. Mainnet executed the removal at block 26455823,
so pin the fork to the block before it to reproduce the script output:

```bash
forge test --match-contract RemoveGuardiansForkTest --fork-url $MAINNET_RPC --fork-block-number 26455822
```

Without `--fork-url` the mainnet fork suites are reported as skipped. On a fork that already includes the removal,
`RemoveGuardiansForkTest` only runs the Security Council redeploy tests, and the tests that need a fork predating v31
are skipped once mainnet runs v31.

The L2 side (the veto seats of the `ZkTokenGovernor` and `ZkGovOpsGovernor`) is handled by
`l2-contracts/script/RedeployZkTokenGovernor.ts` and `l2-contracts/script/RedeployZkGovOpsGovernor.ts`,
which redeploy the governors with the ZK Foundation Safe on Era as `VETO_GUARDIAN` and print the timelock
role migration to propose on the current governors (TPP and GAP respectively).
