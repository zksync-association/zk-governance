// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {DeploySupermajorityGovernorEraMainnet} from "script/DeploySupermajorityGovernorEraMainnet.s.sol";
import {ZkProtocolUpgradeDeploymentConfig} from "council/script/configs/ZkProtocolUpgradeDeploymentConfig.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "council/script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";

// The Era mainnet Supermajority Governor deploy script with the params passed to its constructor, so each test can
// vary them.
contract DeploySupermajorityGovernorEraMainnetHarness is DeploySupermajorityGovernorEraMainnet {
  DeploymentParams internal params;

  constructor(DeploymentParams memory _params) {
    params = _params;
  }

  function _deploymentParams()
    internal
    view
    override(ZkProtocolUpgradeDeploymentConfig, ZkProtocolUpgradeEraMainnetConfig)
    returns (DeploymentParams memory)
  {
    return params;
  }
}
