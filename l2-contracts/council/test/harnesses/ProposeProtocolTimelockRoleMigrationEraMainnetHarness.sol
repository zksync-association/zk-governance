// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
  ProposeProtocolTimelockRoleMigrationEraMainnet
} from "script/ProposeProtocolTimelockRoleMigrationEraMainnet.s.sol";

/// @notice The Era mainnet role migration script, given the Veto Governor directly rather than through `VETO_GOVERNOR`,
/// so tests running in parallel don't share it.
/// @dev The deployment checks the script runs first are covered by `DeployZkProtocolUpgradeGovernance.t.sol`, so they
/// are skipped here, where no council governance is deployed.
contract ProposeProtocolTimelockRoleMigrationEraMainnetHarness is ProposeProtocolTimelockRoleMigrationEraMainnet {
  address internal immutable VETO_GOVERNOR;

  constructor(address _vetoGovernor) {
    VETO_GOVERNOR = _vetoGovernor;
  }

  function _deployedVetoGovernor() internal view override returns (address) {
    return VETO_GOVERNOR;
  }

  function _validateExistingDeployment() internal view override {}
}
