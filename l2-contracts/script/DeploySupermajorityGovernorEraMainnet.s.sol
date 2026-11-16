// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DeploySupermajorityGovernor} from "script/DeploySupermajorityGovernor.s.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "council/script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";

// Deploys the Supermajority Governor and its override timelock on ZKsync Era mainnet with the ZIP parameters in
// `ZkProtocolUpgradeEraMainnetConfig`.
//
// Usage, from `l2-contracts`, with the deployer passed through the usual forge wallet options, e.g. `--account`:
// `forge script script/DeploySupermajorityGovernorEraMainnet.s.sol:DeploySupermajorityGovernorEraMainnet --zksync
// --rpc-url <era-rpc> --broadcast`
// Omit `--broadcast` for a dry run. Pass the logged addresses to `DeployZkProtocolUpgradeGovernance` as
// `SUPERMAJORITY_GOVERNOR` and `OVERRIDE_TIMELOCK`. After broadcasting, add `--sig "check()"` with those two and
// `DEPLOYER` set to check the deployment on chain.
contract DeploySupermajorityGovernorEraMainnet is DeploySupermajorityGovernor, ZkProtocolUpgradeEraMainnetConfig {
  // Script entrypoint
  function run() public override {
    DeploySupermajorityGovernor.run();
  }
}
