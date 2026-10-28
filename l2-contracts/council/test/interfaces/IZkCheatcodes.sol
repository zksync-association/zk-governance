// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice The foundry-zksync cheatcodes the tests use, which forge-std does not declare. Call them on the cheatcode
/// address, as `IZkCheatcodes(address(vm))`.
interface IZkCheatcodes {
  /// @notice Runs the next CREATE or CALL in the EVM instead of EraVM.
  function zkVmSkip() external;
}
