// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The parts of an OpenZeppelin `TimelockController` the checks read, the same in v4 and v5.
interface ITimelockRoles {
  function PROPOSER_ROLE() external view returns (bytes32);
  function EXECUTOR_ROLE() external view returns (bytes32);
  function CANCELLER_ROLE() external view returns (bytes32);
  function getMinDelay() external view returns (uint256);
  function hasRole(bytes32 _role, address _account) external view returns (bool);
}
