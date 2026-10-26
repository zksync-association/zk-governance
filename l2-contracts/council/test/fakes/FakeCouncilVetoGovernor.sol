// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

// Stands in for the veto governor a council governor submits successful proposals to. Like a real governor, it
// identifies a proposal by the hash of its actions and description, and it reports each submitted proposal as pending,
// with a fixed deadline and no ETA. It reverts for any proposal it was never given.
contract FakeCouncilVetoGovernor {
  uint256 public constant PROPOSAL_DEADLINE = 2_000_000_000;

  mapping(uint256 proposalId => bool) public isSubmitted;

  error FakeCouncilVetoGovernor_UnknownProposal(uint256 proposalId);

  function propose(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description
  ) external returns (uint256 _proposalId) {
    _proposalId = uint256(keccak256(abi.encode(_targets, _values, _calldatas, keccak256(bytes(_description)))));
    isSubmitted[_proposalId] = true;
  }

  function state(uint256 _proposalId) external view returns (IGovernor.ProposalState) {
    _revertIfUnknown(_proposalId);
    return IGovernor.ProposalState.Pending;
  }

  function proposalDeadline(uint256 _proposalId) external view returns (uint256) {
    _revertIfUnknown(_proposalId);
    return PROPOSAL_DEADLINE;
  }

  function proposalEta(uint256 _proposalId) external view returns (uint256) {
    _revertIfUnknown(_proposalId);
    return 0;
  }

  function _revertIfUnknown(uint256 _proposalId) internal view {
    if (!isSubmitted[_proposalId]) {
      revert FakeCouncilVetoGovernor_UnknownProposal(_proposalId);
    }
  }
}
