// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

// A settable stand-in for the veto governor a council governor submits successful proposals to. It identifies a
// proposal by the hash of its actions and description, as a real governor does, and starts each submitted proposal
// pending with `PROPOSAL_DEADLINE` and no ETA. Tests set its state, deadline and ETA directly.
contract FakeCouncilVetoGovernor {
  uint256 public constant PROPOSAL_DEADLINE = 2_000_000_000;

  mapping(uint256 proposalId => bool) public isSubmitted;
  mapping(uint256 proposalId => IGovernor.ProposalState) public proposalStates;
  mapping(uint256 proposalId => uint256) public proposalDeadlines;
  mapping(uint256 proposalId => uint256) public proposalEtas;

  function state(uint256 _proposalId) external view returns (IGovernor.ProposalState) {
    return proposalStates[_proposalId];
  }

  function proposalDeadline(uint256 _proposalId) external view returns (uint256) {
    return proposalDeadlines[_proposalId];
  }

  function proposalEta(uint256 _proposalId) external view returns (uint256) {
    return proposalEtas[_proposalId];
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
    proposalDeadlines[_proposalId] = PROPOSAL_DEADLINE;
  }

  function execute(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) external payable returns (uint256 _proposalId) {
    _proposalId = _hashProposal(_targets, _values, _calldatas, _descriptionHash);
    proposalStates[_proposalId] = IGovernor.ProposalState.Executed;
  }

  function setState(uint256 _proposalId, IGovernor.ProposalState _state) external {
    proposalStates[_proposalId] = _state;
  }

  function setDeadline(uint256 _proposalId, uint256 _deadline) external {
    proposalDeadlines[_proposalId] = _deadline;
  }

  function setEta(uint256 _proposalId, uint256 _eta) external {
    proposalEtas[_proposalId] = _eta;
  }

  function _hashProposal(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal pure returns (uint256) {
    return uint256(keccak256(abi.encode(_targets, _values, _calldatas, _descriptionHash)));
  }
}
