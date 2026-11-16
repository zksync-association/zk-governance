// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Stands in for the Supermajority Governor, which is an OpenZeppelin v4 contract this project cannot deploy. It
// reports the settings the deployment checks read, as a deployed governor would.
contract FakeSupermajorityGovernor {
  struct Settings {
    string name;
    address token;
    address timelock;
    uint256 votingDelay;
    uint256 votingPeriod;
    uint256 proposalThreshold;
    uint256 quorum;
    uint64 lateQuorumVoteExtension;
  }

  Settings internal settings;

  constructor(Settings memory _settings) {
    settings = _settings;
  }

  function name() external view returns (string memory) {
    return settings.name;
  }

  function token() external view returns (address) {
    return settings.token;
  }

  function timelock() external view returns (address) {
    return settings.timelock;
  }

  function clock() external view returns (uint48) {
    return uint48(block.timestamp);
  }

  function votingDelay() external view returns (uint256) {
    return settings.votingDelay;
  }

  function votingPeriod() external view returns (uint256) {
    return settings.votingPeriod;
  }

  function proposalThreshold() external view returns (uint256) {
    return settings.proposalThreshold;
  }

  function quorum(uint256) external view returns (uint256) {
    return settings.quorum;
  }

  function lateQuorumVoteExtension() external view returns (uint64) {
    return settings.lateQuorumVoteExtension;
  }
}
