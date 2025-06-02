// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "./IMintable.sol";

/// @title IZkMinterRateLimiterV1Factory
/// @notice Interface for the ZkMinterRateLimiterV1Factory contract
interface IZkMinterRateLimiterV1Factory {
  /// @notice Emitted when a new `ZkMinterRateLimiterV1` is created.
  /// @param minterRateLimiter The address of the newly deployed `ZkMinterRateLimiterV1`.
  /// @param mintable A contract used as a target when calling mint.
  /// @param admin The address that will have admin privileges.
  /// @param mintRateLimit The maximum number of tokens that may be minted within the rate limit window.
  /// @param mintRateLimitWindow The duration in seconds of the rate limit window.
  event MinterRateLimiterCreated(
    address indexed minterRateLimiter,
    IMintable mintable,
    address admin,
    uint256 mintRateLimit,
    uint48 mintRateLimitWindow
  );

  /// @notice Returns the bytecode hash used for CREATE2 deployments
  function BYTECODE_HASH() external view returns (bytes32);

  /// @notice Deploys a new `ZkMinterRateLimiterV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintRateLimit The maximum number of tokens that may be minted within the rate limit window.
  /// @param _mintRateLimitWindow The duration in seconds of the rate limit window.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterRateLimiterAddress The address of the newly deployed `ZkMinterRateLimiterV1`.
  function createMinter(
    IMintable _mintable,
    address _admin,
    uint256 _mintRateLimit,
    uint48 _mintRateLimitWindow,
    uint256 _saltNonce
  ) external returns (address _minterRateLimiterAddress);

  /// @notice Computes the address of a `ZkMinterRateLimiterV1` deployed via this factory.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintRateLimit The maximum number of tokens that may be minted within the rate limit window.
  /// @param _mintRateLimitWindow The duration in seconds of the rate limit window.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return _minterRateLimiterAddress The address of the `ZkMinterRateLimiterV1`.
  function getMinter(
    IMintable _mintable,
    address _admin,
    uint256 _mintRateLimit,
    uint48 _mintRateLimitWindow,
    uint256 _saltNonce
  ) external view returns (address _minterRateLimiterAddress);
}
