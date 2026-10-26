// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

// Stands in for the veto governor a council governor submits successful proposals to. Like a real governor, it
// identifies a proposal by the hash of its actions and description. A submitted proposal is pending until it is
// executed, or until a test defeats it to simulate a veto. Each has a fixed deadline and no ETA. It reverts for any
// proposal it was never given.
contract FakeCouncilVetoGovernor {
  error FakeCouncilVetoGovernor__UnknownProposal(uint256 proposalId);

  uint256 public constant PROPOSAL_DEADLINE = 2_000_000_000;

  mapping(uint256 proposalId => bool) public isSubmitted;
  mapping(uint256 proposalId => IGovernor.ProposalState) internal proposalStates;

  function state(uint256 _proposalId) external view returns (IGovernor.ProposalState) {
    _revertIfProposalIsUnknown(_proposalId);
    return proposalStates[_proposalId];
  }

  function proposalDeadline(uint256 _proposalId) external view returns (uint256) {
    _revertIfProposalIsUnknown(_proposalId);
    return PROPOSAL_DEADLINE;
  }

  function proposalEta(uint256 _proposalId) external view returns (uint256) {
    _revertIfProposalIsUnknown(_proposalId);
    return 0;
  }

  function propose(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    string memory _description
  ) external returns (uint256 _proposalId) {
    _proposalId = _hashProposal(_targets, _values, _calldatas, keccak256(bytes(_description)));
    isSubmitted[_proposalId] = true;
    proposalStates[_proposalId] = IGovernor.ProposalState.Pending;
  }

  function execute(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) external payable returns (uint256 _proposalId) {
    _proposalId = _hashProposal(_targets, _values, _calldatas, _descriptionHash);
    _revertIfProposalIsUnknown(_proposalId);
    proposalStates[_proposalId] = IGovernor.ProposalState.Executed;
  }

  // Simulates token holders vetoing a submitted proposal.
  function defeat(uint256 _proposalId) external {
    _revertIfProposalIsUnknown(_proposalId);
    proposalStates[_proposalId] = IGovernor.ProposalState.Defeated;
  }

  function _hashProposal(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal pure returns (uint256) {
    return uint256(keccak256(abi.encode(_targets, _values, _calldatas, _descriptionHash)));
  }

  function _revertIfProposalIsUnknown(uint256 _proposalId) internal view {
    if (!isSubmitted[_proposalId]) {
      revert FakeCouncilVetoGovernor__UnknownProposal(_proposalId);
    }
  }
}
