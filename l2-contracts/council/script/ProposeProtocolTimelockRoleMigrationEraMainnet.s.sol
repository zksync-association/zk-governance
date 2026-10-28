// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ProposeProtocolTimelockRoleMigration} from "script/ProposeProtocolTimelockRoleMigration.s.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";

// The Protocol Timelock role migration on ZKsync Era mainnet.
//
// Usage, from `l2-contracts/council`, with the deployed council governance's addresses and deployer in
// `COUNCIL_TOKEN`, `COUNCIL_GOVERNOR`, `VETO_GOVERNOR`, `SUPERMAJORITY_GOVERNOR`, `OVERRIDE_TIMELOCK` and `DEPLOYER`:
// `forge script
// script/ProposeProtocolTimelockRoleMigrationEraMainnet.s.sol:ProposeProtocolTimelockRoleMigrationEraMainnet
// --zksync --rpc-url <era-rpc> --broadcast --account <delegate-keystore-account> --sender <delegate-address>`, where
// the delegate's votes meet `ZkProtocolGovernor`'s proposal threshold.
// Also set `SUPERMAJORITY_GOVERNOR_DEPLOYER=<addr>` if `DeploySupermajorityGovernor` was run from a different account.
contract ProposeProtocolTimelockRoleMigrationEraMainnet is
  ProposeProtocolTimelockRoleMigration,
  ZkProtocolUpgradeEraMainnetConfig
{
  // The governor that holds the Protocol Timelock roles on Era mainnet before the migration.
  address internal constant PROTOCOL_GOVERNOR = 0x76705327e682F2d96943280D99464Ab61219e34f;

  // Script entrypoint
  function run() public override {
    ProposeProtocolTimelockRoleMigration.run();
  }

  function _protocolGovernor() internal view virtual override returns (address) {
    return PROTOCOL_GOVERNOR;
  }
}
