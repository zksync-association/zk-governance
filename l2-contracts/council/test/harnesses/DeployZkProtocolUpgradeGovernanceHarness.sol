// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployZkProtocolUpgradeGovernanceEraMainnet} from "script/DeployZkProtocolUpgradeGovernanceEraMainnet.s.sol";
import {ZkProtocolUpgradeDeploymentConfig} from "script/configs/ZkProtocolUpgradeDeploymentConfig.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";

// The Era mainnet deploy script with everything a test varies passed to its constructor: the params, the Supermajority
// Governor and override timelock, which the script otherwise reads from the environment, and the Supermajority
// Governor's deployer. Environment variables are shared by tests running in parallel, so the harness takes these
// through its constructor instead.
contract DeployZkProtocolUpgradeGovernanceEraMainnetHarness is DeployZkProtocolUpgradeGovernanceEraMainnet {
  DeploymentParams internal params;
  address public supermajorityGovernor;
  TimelockController public overrideTimelock;
  // When zero, the Supermajority Governor shares the council deployer.
  address internal supermajorityGovernorDeployer;

  constructor(
    DeploymentParams memory _params,
    address _supermajorityGovernor,
    TimelockController _overrideTimelock,
    address _supermajorityGovernorDeployer
  ) {
    params = _params;
    supermajorityGovernor = _supermajorityGovernor;
    overrideTimelock = _overrideTimelock;
    supermajorityGovernorDeployer = _supermajorityGovernorDeployer;
  }

  function _supermajorityGovernorContracts() internal view override returns (address, TimelockController) {
    return (supermajorityGovernor, overrideTimelock);
  }

  function _supermajorityGovernorDeployer(address _default) internal view override returns (address) {
    return supermajorityGovernorDeployer != address(0) ? supermajorityGovernorDeployer : _default;
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
