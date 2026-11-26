// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IChainAssetHandler {
  /// @notice Pauses migration functions.
  function pauseMigration() external;

  /// @notice Unpauses migration functions.
  function unpauseMigration() external;
}
