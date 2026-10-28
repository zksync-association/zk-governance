// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {BasicCouncilVetoGovernor} from "council-governance/BasicCouncilVetoGovernor.sol";

/// @title ZkProtocolUpgradeVetoGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @custom:security-contact security@zksync.io
/// @notice A governor through which token holders can veto proposals submitted by a council governor. A proposal here
/// passes by default: it succeeds at the end of its voting period unless AGAINST votes reach the veto threshold, in
/// which case it is defeated. Passed proposals are queued and executed through a timelock. The veto threshold is a
/// number of votes, set at deployment and changeable by the governor's admin, rather than a share of the token supply.
///
/// Three further safeguards apply. If AGAINST votes reach a set percentage of the veto threshold, the voting period is
/// extended once, giving holders more time to respond to an emerging veto. A guardian can veto a proposal outright
/// while it is pending or active. And an override role can revive a defeated proposal, whether defeated by token
/// holders or by the guardian, within a set window after its voting period ends.
/// @dev The veto threshold is checkpointed. Each proposal is judged against the threshold in force at its snapshot, so
/// a change made at or before a proposal's snapshot applies to it, and a change made after does not.
///
/// The fraction-of-supply threshold settings inherited from `GovernorVotesVetoThresholdFraction` are unused: the
/// numerator can only be set to zero, at construction or through `updateVetoThresholdNumerator`, and nothing is
/// recorded, so `vetoThresholdNumerator` always returns zero.
contract ZkProtocolUpgradeVetoGovernor is BasicCouncilVetoGovernor {
  using Checkpoints for Checkpoints.Trace208;

  /// @notice Emitted when the veto threshold is set, at deployment or by the admin.
  /// @param oldVetoThreshold The veto threshold before the change, zero at deployment.
  /// @param newVetoThreshold The veto threshold after the change.
  event VetoThresholdSet(uint256 oldVetoThreshold, uint256 newVetoThreshold);

  /// @notice Thrown when the veto threshold is set to zero, which would veto every proposal.
  error ZkProtocolUpgradeVetoGovernor__InvalidVetoThreshold();

  /// @notice Thrown when a fraction-of-supply veto threshold other than zero is set, at construction or by the admin.
  error ZkProtocolUpgradeVetoGovernor__VetoThresholdFractionDisabled();

  /// @notice The veto threshold, recorded at each timepoint it was set.
  Checkpoints.Trace208 private vetoThresholdCheckpoints;

  /// @param _params The base governor's constructor parameters. `vetoThresholdNumerator` must be zero, since this
  /// governor sets its veto threshold in votes instead.
  /// @param _initialVetoThreshold The number of AGAINST votes that vetoes a proposal. Must be non-zero.
  constructor(ConstructorParams memory _params, uint256 _initialVetoThreshold) BasicCouncilVetoGovernor(_params) {
    _setVetoThreshold(_initialVetoThreshold);
  }

  /// @notice Returns the number of AGAINST votes that vetoes a proposal whose snapshot is `_timepoint`.
  /// @param _timepoint The timepoint to read the veto threshold at.
  /// @return The latest veto threshold set at or before `_timepoint`.
  function vetoThreshold(uint256 _timepoint) public view virtual override returns (uint256) {
    return _optimisticUpperLookupRecent(vetoThresholdCheckpoints, _timepoint);
  }

  /// @notice Sets the number of AGAINST votes that vetoes a proposal, from the current timepoint on. Proposals whose
  /// snapshot is earlier keep the threshold in force at their snapshot. Only the governor's admin can call it.
  /// @param _newVetoThreshold The new veto threshold, in votes. Must be non-zero.
  function setVetoThreshold(uint256 _newVetoThreshold) external virtual onlyGovernance {
    _setVetoThreshold(_newVetoThreshold);
  }

  /// @notice Records a new veto threshold at the current timepoint.
  /// @param _newVetoThreshold The new veto threshold, in votes. Must be non-zero.
  function _setVetoThreshold(uint256 _newVetoThreshold) internal virtual {
    if (_newVetoThreshold == 0) {
      revert ZkProtocolUpgradeVetoGovernor__InvalidVetoThreshold();
    }
    (uint256 _oldVetoThreshold,) = vetoThresholdCheckpoints.push(clock(), SafeCast.toUint208(_newVetoThreshold));
    emit VetoThresholdSet(_oldVetoThreshold, _newVetoThreshold);
  }

  /// @notice Accepts only a zero fraction-of-supply numerator, and records nothing, since the veto threshold is set in
  /// votes with `setVetoThreshold`. Runs at construction and for every `updateVetoThresholdNumerator` call.
  /// @param _newVetoThresholdNumerator The new fraction-of-supply numerator.
  function _updateVetoThresholdNumerator(uint256 _newVetoThresholdNumerator) internal virtual override {
    if (_newVetoThresholdNumerator != 0) {
      revert ZkProtocolUpgradeVetoGovernor__VetoThresholdFractionDisabled();
    }
  }
}
