// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IMintHook
/// @author [ScopeLift](https://scopelift.co)
/// @notice Interface for hooks that can be called before minting in ZkCappedMinterV2
interface IMintHook {
  /// @notice Called before minting tokens
  /// @param minter The address attempting to mint tokens
  /// @param receiver The address that will receive the minted tokens
  /// @param amount The amount of tokens to be minted
  /// @dev This function should revert with custom errors to prevent minting
  function beforeMint(address minter, address receiver, uint256 amount) external;
}
