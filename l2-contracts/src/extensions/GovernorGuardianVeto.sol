// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

/// @title GovernorGuardianVeto
/// @author [ScopeLift](https://scopelift.co)
/// @notice An abstract extension contract that allows a trusted address to cancel a proposal if it is pending or
/// active.
/// @custom:security-contact security@zksync.io
abstract contract GovernorGuardianVeto is Governor {
  /// @notice An immutable address which can cancel proposals while they are pending or active.
  address public immutable VETO_GUARDIAN;

  /// @notice An immutable address which can cancel proposals while they are pending or active.
  error GovernorGuardianVeto_UncancelableProposalState();

  /// @notice Thrown if an address tries to perform an action for which it is not authorized.
  error GovernorGuardianVeto_Unauthorized();

  /// @param _vetoGuardian The address to set as the immutable `VETO_GUARDIAN`.
  constructor(address _vetoGuardian) {
    VETO_GUARDIAN = _vetoGuardian;
  }

  /// @notice This function will cancel a proposal, and can only be called by the guardian while the proposal is either
  /// pending or active.
  /// @param _targets A list of contracts to call when a proposal is executed.
  /// @param _values A list of values to send when calling each target.
  /// @param _calldatas A list of calldatas to use when calling the targets.
  /// @param _descriptionHash A hash of the proposal description.
  function cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) public virtual override returns (uint256) {
    if (_msgSender() != VETO_GUARDIAN) {
      revert GovernorGuardianVeto_Unauthorized();
    }
    uint256 _proposalId = hashProposal(_targets, _values, _calldatas, _descriptionHash);

    ProposalState _proposalState = state(_proposalId);

    if (_proposalState != ProposalState.Active && _proposalState != ProposalState.Pending) {
      revert GovernorGuardianVeto_UncancelableProposalState();
    }
    return _cancel(_targets, _values, _calldatas, _descriptionHash);
  }
}
