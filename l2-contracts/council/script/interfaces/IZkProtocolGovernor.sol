// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The parts of `ZkProtocolGovernor` the checks read. `DeploySupermajorityGovernor` deploys it as the Supermajority
// Governor; the council project cannot import it, since it is built on OpenZeppelin v4.
interface IZkProtocolGovernor {
  function name() external view returns (string memory);
  function token() external view returns (address);
  function timelock() external view returns (address);
  function clock() external view returns (uint48);
  function votingDelay() external view returns (uint256);
  function votingPeriod() external view returns (uint256);
  function proposalThreshold() external view returns (uint256);
  function quorum(uint256 _timepoint) external view returns (uint256);
  function lateQuorumVoteExtension() external view returns (uint64);
}
