// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "./IMintable.sol";

/// @title IZkMinterRateLimiterV1
/// @notice Interface for the ZkMinterRateLimiterV1 contract
interface IZkMinterRateLimiterV1 is IMintable {
  /// @notice Emitted when the mintable contract is updated.
  event MintableUpdated(IMintable indexed previousMintable, IMintable indexed newMintable);

  /// @notice Emitted when the mint rate limit is updated.
  event MintRateLimitUpdated(uint256 indexed previousMintRateLimit, uint256 indexed newMintRateLimit);

  /// @notice Emitted when the mint rate limit window is updated.
  event MintRateLimitWindowUpdated(uint48 indexed previousMintRateLimitWindow, uint48 indexed newMintRateLimitWindow);

  /// @notice Emitted when tokens are minted.
  event Minted(address indexed minter, address indexed to, uint256 amount);

  /// @notice Emitted when the contract is closed.
  event Closed(address closer);

  /// @notice Error for when the rate limit is exceeded.
  error ZkMinterRateLimiterV1__MintRateLimitExceeded(address minter, uint256 amount);

  /// @notice Error for when the contract is closed.
  error ZkMinterRateLimiterV1__ContractClosed();

  /// @notice A contract used as a target when calling mint.
  function mintable() external view returns (IMintable);

  /// @notice The number of tokens minted in each mint window.
  function mintedInWindow(uint48 mintWindowStart) external view returns (uint256);

  /// @notice The maximum number of tokens that may be minted by the minter in a single mint rate limit window.
  function mintRateLimit() external view returns (uint256);

  /// @notice The number of seconds in a mint rate limit window.
  function mintRateLimitWindow() external view returns (uint48);

  /// @notice The timestamp when minting can begin.
  function START_TIME() external view returns (uint48);

  /// @notice The unique identifier constant used to represent the minter role.
  function MINTER_ROLE() external view returns (bytes32);

  /// @notice The unique identifier constant used to represent the pauser role.
  function PAUSER_ROLE() external view returns (bytes32);

  /// @notice Whether the contract has been permanently closed.
  function closed() external view returns (bool);

  /// @notice Mints a given amount of tokens to a given address, so long as the rate limit is not exceeded.
  /// @param _to The address that will receive the new tokens.
  /// @param _amount The quantity of tokens that will be minted.
  function mint(address _to, uint256 _amount) external;

  /// @notice Updates the mintable contract that this rate limiter will use for minting.
  /// @param _mintable The new mintable contract to use.
  function updateMintable(IMintable _mintable) external;

  /// @notice Updates the maximum number of tokens that can be minted during the rate limit window.
  /// @param _mintRateLimit The new maximum number of tokens that can be minted during the rate limit window.
  function updateMintRateLimit(uint256 _mintRateLimit) external;

  /// @notice Updates the duration of the rate limit window in seconds.
  /// @param _mintRateLimitWindow The new duration of the rate limit window in seconds.
  function updateMintRateLimitWindow(uint48 _mintRateLimitWindow) external;

  /// @notice Pauses token minting
  function pause() external;

  /// @notice Unpauses token minting
  function unpause() external;

  /// @notice Permanently closes the contract, preventing any future minting.
  function close() external;

  /// @notice Calculates the start timestamp of the current mint window.
  /// @return The timestamp marking the start of the current mint window.
  function currentMintWindowStart() external view returns (uint48);
}
