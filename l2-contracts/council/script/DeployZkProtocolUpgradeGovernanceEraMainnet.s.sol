// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {DeployZkProtocolUpgradeGovernance} from "script/DeployZkProtocolUpgradeGovernance.s.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";

// Deploys the protocol upgrade council governance on ZKsync Era mainnet with the ZIP parameters in
// `ZkProtocolUpgradeEraMainnetConfig`.
//
// Usage, from `l2-contracts/council`, with the deployer passed through the usual forge wallet options, e.g.
// `--account`: `SUPERMAJORITY_GOVERNOR=<addr> OVERRIDE_TIMELOCK=<addr> forge script
// script/DeployZkProtocolUpgradeGovernanceEraMainnet.s.sol:DeployZkProtocolUpgradeGovernanceEraMainnet --zksync
// --rpc-url <era-rpc> --broadcast`
// Also set `SUPERMAJORITY_GOVERNOR_DEPLOYER=<addr>` if `DeploySupermajorityGovernor` was run from a different account.
// Omit `--broadcast` for a dry run against the live chain state. Add `--sig "check()"` to check an existing deployment.
contract DeployZkProtocolUpgradeGovernanceEraMainnet is
  DeployZkProtocolUpgradeGovernance,
  ZkProtocolUpgradeEraMainnetConfig
{
  // Script entrypoint
  function run() public override {
    DeployZkProtocolUpgradeGovernance.run();
  }
}
