// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

// Stands in for the veto governor a council governor submits successful proposals to. It records the last proposal
// submitted and reports every proposal as pending, with no ETA.
contract FakeCouncilVetoGovernor {
  uint256 public constant PROPOSAL_DEADLINE = 2_000_000_000;

  address[] internal submittedTargets;
  string public submittedDescription;
  uint256 public submittedProposalCount;

  function propose(address[] memory _targets, uint256[] memory, bytes[] memory, string memory _description)
    external
    returns (uint256)
  {
    submittedTargets = _targets;
    submittedDescription = _description;
    submittedProposalCount += 1;
    return 0;
  }

  function submittedTarget(uint256 _index) external view returns (address) {
    return submittedTargets[_index];
  }

  function state(uint256) external pure returns (IGovernor.ProposalState) {
    return IGovernor.ProposalState.Pending;
  }

  function proposalDeadline(uint256) external pure returns (uint256) {
    return PROPOSAL_DEADLINE;
  }

  function proposalEta(uint256) external pure returns (uint256) {
    return 0;
  }
}
