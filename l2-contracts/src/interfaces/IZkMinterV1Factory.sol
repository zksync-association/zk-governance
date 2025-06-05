// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";

/// @title IZkMinterV1Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice An interface with all of the shared methods for a ZK factory.
/// @custom:security-contact security@matterlabs.dev
interface IZkMinterV1Factory {
  /// @notice Deploys a new `ZkMinter` contract using CREATE2. This method takes a bytes argument
  /// and is meant to be used in a unified factory for all capped minter extensions.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args The args to deploy ZkMinter.
  /// @return The address of the newly deployed `ZkMinter`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address);
}
