// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DeployBase} from "./DeployBase.sol";
import {ZkProtocolUpgradeDeploymentConfig} from "./configs/ZkProtocolUpgradeDeploymentConfig.sol";
import {IZkProtocolGovernor} from "./interfaces/IZkProtocolGovernor.sol";

// Checks a deployed Supermajority Governor (`ZkProtocolGovernor`) and its override timelock against `DeploymentParams`:
// the governor's settings, the timelock's delay, that the governor is the timelock's proposer and canceller, that
// anyone can execute, that the timelock administers itself, and that the deployer holds no role on it. It also checks
// that the params fit together.
//
// The Supermajority Governor and its timelock are OpenZeppelin v4 contracts, so `DeploySupermajorityGovernor` deploys
// them from the main l2-contracts project. `DeployZkProtocolUpgradeGovernance` in `l2-contracts/council`, which uses
// OpenZeppelin v5, then makes that timelock the Veto Governor's `vetoOverrideRole`.
//
// `DeploySupermajorityGovernor` runs these checks on its own output after deploying.
// `DeployZkProtocolUpgradeGovernance` runs them before broadcasting, because once the Veto Governor exists, replacing a
// wrong override timelock takes a full governance proposal.
//
// Both l2-contracts projects compile the same checks: the governor is read through an interface, and the timelock
// through whichever OpenZeppelin `TimelockController` the project maps, v4 or v5, since the checks call only functions
// both versions share.
abstract contract SupermajorityGovernorChecks is DeployBase, ZkProtocolUpgradeDeploymentConfig {
  // Rejects a `zkToken` with no code, and a veto override window (`vetoGovernorVetoOverrideDuration`) too short to fit
  // a Supermajority Governor override: its voting delay, voting period and late-quorum extension, then the override
  // timelock's delay.
  function _validateSupermajorityGovernorParams(DeploymentParams memory _params) internal view {
    if (_params.zkToken.code.length == 0) {
      revert("SupermajorityGovernorChecks: zkToken has no code; set it to the ZK token");
    }
    // After a veto, a Supermajority Governor proposal to override it needs its voting delay, voting period and a
    // possible late-quorum extension, then the override timelock's delay, all within the veto override window.
    uint256 _longestOverride = uint256(_params.supermajorityGovernorVotingDelay)
      + _params.supermajorityGovernorVotingPeriod + _params.supermajorityGovernorLateQuorumVoteExtension
      + _params.overrideTimelockMinDelay;
    // The override must also be queued and executed after the Supermajority Governor's vote ends, so the window has to
    // be strictly longer.
    if (_params.vetoGovernorVetoOverrideDuration <= _longestOverride) {
      revert("SupermajorityGovernorChecks: vetoGovernorVetoOverrideDuration is too short for a supermajority override");
    }
  }

  // Runs every check of the Supermajority Governor and override timelock deployed by `_deployer`.
  function _validateSupermajorityGovernorDeployment(
    DeploymentParams memory _params,
    address _supermajorityGovernor,
    address _overrideTimelock,
    address _deployer
  ) internal view {
    if (_supermajorityGovernor.code.length == 0 || _overrideTimelock.code.length == 0) {
      revert("SupermajorityGovernorChecks: the Supermajority Governor or override timelock is not deployed");
    }
    _validateSupermajorityGovernor(_params, IZkProtocolGovernor(_supermajorityGovernor), _overrideTimelock);
    _validateOverrideTimelock(
      _params, TimelockController(payable(_overrideTimelock)), _supermajorityGovernor, _deployer
    );
  }

  function _validateSupermajorityGovernor(
    DeploymentParams memory _params,
    IZkProtocolGovernor _governor,
    address _overrideTimelock
  ) internal view {
    if (!_eq(_governor.name(), _params.supermajorityGovernorName)) {
      revert("SupermajorityGovernorChecks: Supermajority Governor name does not match the params");
    }
    if (_governor.token() != _params.zkToken) {
      revert("SupermajorityGovernorChecks: Supermajority Governor token is not the ZK token");
    }
    if (_governor.timelock() != _overrideTimelock) {
      revert("SupermajorityGovernorChecks: the Supermajority Governor's timelock is not the override timelock");
    }
    if (_governor.votingDelay() != _params.supermajorityGovernorVotingDelay) {
      revert("SupermajorityGovernorChecks: Supermajority Governor voting delay does not match the params");
    }
    if (_governor.votingPeriod() != _params.supermajorityGovernorVotingPeriod) {
      revert("SupermajorityGovernorChecks: Supermajority Governor voting period does not match the params");
    }
    if (_governor.proposalThreshold() != _params.supermajorityGovernorProposalThreshold) {
      revert("SupermajorityGovernorChecks: Supermajority Governor proposal threshold does not match the params");
    }
    if (_governor.quorum(_governor.clock()) != _params.supermajorityGovernorQuorum) {
      revert("SupermajorityGovernorChecks: Supermajority Governor quorum does not match the params");
    }
    if (_governor.lateQuorumVoteExtension() != _params.supermajorityGovernorLateQuorumVoteExtension) {
      revert("SupermajorityGovernorChecks: Supermajority Governor late-quorum extension does not match the params");
    }
  }

  // Checks that the override timelock has the configured delay, that the Supermajority Governor is its proposer and
  // canceller, that anyone can execute, that it administers itself, and that `_deployer` holds no role on it.
  function _validateOverrideTimelock(
    DeploymentParams memory _params,
    TimelockController _timelock,
    address _supermajorityGovernor,
    address _deployer
  ) internal view {
    if (_timelock.getMinDelay() != _params.overrideTimelockMinDelay) {
      revert("SupermajorityGovernorChecks: override timelock delay does not match the params");
    }
    if (!_timelock.hasRole(_timelock.PROPOSER_ROLE(), _supermajorityGovernor)) {
      revert("SupermajorityGovernorChecks: the Supermajority Governor is not the override timelock's proposer");
    }
    if (!_timelock.hasRole(_timelock.CANCELLER_ROLE(), _supermajorityGovernor)) {
      revert("SupermajorityGovernorChecks: the Supermajority Governor is not the override timelock's canceller");
    }
    if (!_timelock.hasRole(_timelock.EXECUTOR_ROLE(), address(0))) {
      revert("SupermajorityGovernorChecks: override timelock execution is not open to everyone");
    }
    if (!_timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(_timelock))) {
      revert("SupermajorityGovernorChecks: the override timelock does not administer itself");
    }
    if (
      // TIMELOCK_ADMIN_ROLE is OpenZeppelin v4's admin role and DEFAULT_ADMIN_ROLE (zero) is v5's, so a wrong timelock
      // the deployer still administers is caught too.
      _timelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer) || _timelock.hasRole(bytes32(0), _deployer)
        || _timelock.hasRole(_timelock.PROPOSER_ROLE(), _deployer)
        || _timelock.hasRole(_timelock.CANCELLER_ROLE(), _deployer)
        || _timelock.hasRole(_timelock.EXECUTOR_ROLE(), _deployer)
    ) {
      revert("SupermajorityGovernorChecks: the deployer holds a role on the override timelock");
    }
  }
}
