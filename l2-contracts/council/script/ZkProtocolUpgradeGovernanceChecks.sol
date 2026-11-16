// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";
import {ZkProtocolUpgradeVetoGovernor} from "src/ZkProtocolUpgradeVetoGovernor.sol";
import {SupermajorityGovernorChecks} from "script/SupermajorityGovernorChecks.sol";

// Checks a protocol upgrade governance deployment against its params: every contract's settings, the wiring between
// them, the handover of every admin role to the governance admin, and that the deployer kept no privileges. The deploy
// script runs these checks after deploying, and other scripts inherit them to check an existing deployment.
abstract contract ZkProtocolUpgradeGovernanceChecks is SupermajorityGovernorChecks {
  struct Deployment {
    CouncilERC20 councilToken;
    ZkProtocolUpgradeCouncilGovernor councilGovernor;
    ZkProtocolUpgradeVetoGovernor vetoGovernor;
    // From `DeploySupermajorityGovernor`. The override timelock is an OpenZeppelin v4 `TimelockController`, read
    // through the v5 type, whose ABI matches for the functions used here; its admin role is `TIMELOCK_ADMIN_ROLE`.
    address supermajorityGovernor;
    TimelockController overrideTimelock;
  }

  // Reads an existing deployment's addresses from `COUNCIL_TOKEN`, `COUNCIL_GOVERNOR`, `VETO_GOVERNOR`,
  // `SUPERMAJORITY_GOVERNOR` and `OVERRIDE_TIMELOCK`.
  function _deploymentFromEnv() internal view returns (Deployment memory) {
    return Deployment({
      councilToken: CouncilERC20(vm.envAddress("COUNCIL_TOKEN")),
      councilGovernor: ZkProtocolUpgradeCouncilGovernor(payable(vm.envAddress("COUNCIL_GOVERNOR"))),
      vetoGovernor: ZkProtocolUpgradeVetoGovernor(payable(vm.envAddress("VETO_GOVERNOR"))),
      supermajorityGovernor: vm.envAddress("SUPERMAJORITY_GOVERNOR"),
      overrideTimelock: TimelockController(payable(vm.envAddress("OVERRIDE_TIMELOCK")))
    });
  }

  // Runs every check against a deployment whose council contracts were deployed by `_deployer` and whose Supermajority
  // Governor and override timelock were deployed by `_supermajorityGovernorDeployerAccount`.
  function _validateDeployment(
    DeploymentParams memory _params,
    Deployment memory _deployment,
    address _deployer,
    address _supermajorityGovernorDeployerAccount
  ) internal view {
    _validateCouncilToken(_params, _deployment);
    _validateCouncilGovernor(_params, _deployment);
    _validateVetoGovernor(_params, _deployment, _deployer);
    _validateSupermajorityGovernorDeployment(
      _params,
      _deployment.supermajorityGovernor,
      address(_deployment.overrideTimelock),
      _supermajorityGovernorDeployerAccount
    );
  }

  // The supply check means no account outside `councilMembers`, the deployer included, holds a seat.
  function _validateCouncilToken(DeploymentParams memory _params, Deployment memory _deployment) internal view {
    CouncilERC20 _token = _deployment.councilToken;
    address[] memory _members = _params.councilMembers;

    if (!_eq(_token.name(), _params.councilTokenName)) {
      revert("ZkProtocolUpgradeGovernanceChecks: council token name does not match the params");
    }
    if (!_eq(_token.symbol(), _params.councilTokenSymbol)) {
      revert("ZkProtocolUpgradeGovernanceChecks: council token symbol does not match the params");
    }
    if (_token.owner() != _params.governanceAdmin) {
      revert("ZkProtocolUpgradeGovernanceChecks: council token owner is not the governance admin");
    }
    if (_token.MAX_TOKENS_PER_MEMBER() != _params.votesPerCouncilSeat) {
      revert("ZkProtocolUpgradeGovernanceChecks: council token max tokens per member is not one seat");
    }
    if (_token.totalSupply() != _params.votesPerCouncilSeat * _members.length) {
      revert("ZkProtocolUpgradeGovernanceChecks: council token supply is not one seat per member");
    }
    for (uint256 _i = 0; _i < _members.length; _i += 1) {
      if (
        _token.balanceOf(_members[_i]) != _params.votesPerCouncilSeat
          || _token.getVotes(_members[_i]) != _params.votesPerCouncilSeat
      ) {
        revert(
          string.concat(
            "ZkProtocolUpgradeGovernanceChecks: council member ",
            vm.toString(_members[_i]),
            " does not hold and vote one seat"
          )
        );
      }
    }
  }

  function _validateCouncilGovernor(DeploymentParams memory _params, Deployment memory _deployment) internal view {
    ZkProtocolUpgradeCouncilGovernor _governor = _deployment.councilGovernor;

    if (!_eq(_governor.name(), _params.councilGovernorName)) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor name does not match the params");
    }
    if (address(_governor.token()) != address(_deployment.councilToken)) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor token is not the council token");
    }
    if (_governor.QUORUM() != _params.votesPerCouncilSeat) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor seat size does not match the params");
    }
    if (address(_governor.councilVetoGovernor()) != address(_deployment.vetoGovernor)) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor does not submit proposals to the Veto Governor");
    }
    if (_governor.owner() != _params.governanceAdmin) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor admin is not the governance admin");
    }
    if (_governor.votingDelay() != _params.councilGovernorVotingDelay) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor voting delay does not match the params");
    }
    if (_governor.votingPeriod() != _params.councilGovernorVotingPeriod) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor voting period does not match the params");
    }
    if (_governor.proposalThreshold() != _params.councilGovernorProposalThreshold) {
      revert("ZkProtocolUpgradeGovernanceChecks: council governor proposal threshold does not match the params");
    }
  }

  function _validateVetoGovernor(DeploymentParams memory _params, Deployment memory _deployment, address _deployer)
    internal
    view
  {
    ZkProtocolUpgradeVetoGovernor _governor = _deployment.vetoGovernor;

    if (!_eq(_governor.name(), _params.vetoGovernorName)) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor name does not match the params");
    }
    if (address(_governor.token()) != _params.zkToken) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor token is not the ZK token");
    }
    // Every duration in the params is in seconds, which holds only for a timestamp clock.
    if (!_eq(_governor.CLOCK_MODE(), "mode=timestamp")) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor does not use a timestamp clock");
    }
    if (_governor.COUNCIL() != address(_deployment.councilGovernor)) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor council is not the Council Governor");
    }
    if (_governor.timelock() != _params.protocolTimelock) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor timelock is not the Protocol Timelock");
    }
    if (_governor.owner() != _params.governanceAdmin) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor admin is not the governance admin");
    }
    if (_governor.votingDelay() != _params.vetoGovernorVotingDelay) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor voting delay does not match the params");
    }
    if (_governor.votingPeriod() != _params.vetoGovernorVotingPeriod) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor voting period does not match the params");
    }
    if (_governor.proposalThreshold() != _params.vetoGovernorProposalThreshold) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor proposal threshold does not match the params");
    }
    if (_governor.vetoThreshold(_governor.clock()) != _params.vetoGovernorVetoThreshold) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor veto threshold does not match the params");
    }
    if (_governor.votingPeriodExtension() != _params.vetoGovernorVotingPeriodExtension) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor voting period extension does not match the params");
    }
    if (_governor.minorVetoExtensionThresholdPct() != _params.vetoGovernorVotingPeriodExtensionThresholdPct) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor extension threshold does not match the params");
    }
    if (_governor.vetoGuardian() != _params.vetoGovernorVetoGuardian) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor veto guardian does not match the params");
    }
    if (_governor.vetoGuardian() == _deployer) {
      revert("ZkProtocolUpgradeGovernanceChecks: the deployer is the veto guardian");
    }
    if (_governor.vetoOverrideRole() != address(_deployment.overrideTimelock)) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor veto override role is not the override timelock");
    }
    if (_governor.vetoOverrideDuration() != _params.vetoGovernorVetoOverrideDuration) {
      revert("ZkProtocolUpgradeGovernanceChecks: veto governor override duration does not match the params");
    }
  }
}
