// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";

/// @title ZkMinterRateLimiterV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A contract that implements rate limiting for token minting, allowing authorized minters to collectively mint
/// up to a specified amount within a configurable time period.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterRateLimiterV1 is ZkMinterV1 {
  /// @notice The maximum number of tokens that may be minted by the minter in a single mint rate limit window.
  uint256 public mintRateLimit;

  /// @notice The number of seconds in a mint rate limit window.
  uint48 public mintRateLimitWindow;

  /// @notice The timestamp marking the start of the current mint window.
  uint48 public currentMintWindowStart;

  /// @notice The number of tokens minted in the current mint window.
  uint256 public currentMintWindowMinted;

  /// @notice The timestamp when minting can begin.
  uint48 public immutable START_TIME;

  /// @notice Emitted when the mint rate limit is updated.
  event MintRateLimitUpdated(uint256 indexed previousMintRateLimit, uint256 indexed newMintRateLimit);

  /// @notice Emitted when the mint rate limit window is updated.
  event MintRateLimitWindowUpdated(uint48 indexed previousMintRateLimitWindow, uint48 indexed newMintRateLimitWindow);

  /// @notice Error for when the rate limit is exceeded.
  error ZkMinterRateLimiterV1__MintRateLimitExceeded(address minter, uint256 amount);

  /// @notice Error for when the mint rate limit window is zero.
  error ZkMinterRateLimiterV1__InvalidMintRateLimitWindow();

  /// @notice Error for when the admin is the zero address.
  error ZkMinterRateLimiterV1__InvalidAdmin();

  /// @notice Initializes the rate limiter with the mintable contract, admin, mint rate limit, and mint rate limit
  /// window.
  /// @param _mintable A contract used as a target when calling mint. Any contract that conforms to the IMintable
  /// interface can be used, but in most cases this will be another `ZKMinter` extension or `ZKCappedMinter`.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintRateLimit The maximum number of tokens that can be minted during the rate limit window.
  /// @param _mintRateLimitWindow The duration of the rate limit window in seconds.
  constructor(IMintable _mintable, address _admin, uint256 _mintRateLimit, uint48 _mintRateLimitWindow) {
    if (_admin == address(0)) {
      revert ZkMinterRateLimiterV1__InvalidAdmin();
    }

    _updateMintable(_mintable);
    _updateMintRateLimit(_mintRateLimit);
    _updateMintRateLimitWindow(_mintRateLimitWindow);

    START_TIME = uint48(block.timestamp);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(PAUSER_ROLE, _admin);
  }

  /// @notice Mints a given amount of tokens to a given address, so long as the rate limit is not exceeded.
  /// @dev Users that have minter role can collectively mint a fixed amount for each mint rate limit window.
  /// @param _to The address that will receive the new tokens.
  /// @param _amount The quantity of tokens that will be minted.
  function mint(address _to, uint256 _amount) external {
    _revertIfClosed();
    _requireNotPaused();
    _checkRole(MINTER_ROLE, msg.sender);

    // Roll forward to new window if needed
    if (block.timestamp >= currentMintWindowStart + mintRateLimitWindow) {
      uint48 windowsPassed = uint48(block.timestamp - currentMintWindowStart) / mintRateLimitWindow;
      currentMintWindowStart += windowsPassed * mintRateLimitWindow;
      currentMintWindowMinted = 0;
    }
    _revertIfRateLimitPerMintWindowExceeded(_amount);

    currentMintWindowMinted += _amount;
    mintable.mint(_to, _amount);
    emit Minted(msg.sender, _to, _amount);
  }

  /// @notice Updates the maximum number of tokens that can be minted during the rate limit window.
  /// @param _mintRateLimit The new maximum number of tokens that can be minted during the rate limit window.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  function updateMintRateLimit(uint256 _mintRateLimit) external {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateMintRateLimit(_mintRateLimit);
  }

  /// @notice Updates the duration of the rate limit window in seconds.
  /// @param _mintRateLimitWindow The new duration of the rate limit window in seconds.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  /// @dev The mint rate limit window cannot be set to 0.
  /// @dev This function also resets `currentMintWindowMinted` to 0. Tokens minted in the current window are
  /// disregarded, allowing immediate minting up to the new limit, especially when the window duration is reduced.
  function updateMintRateLimitWindow(uint48 _mintRateLimitWindow) external {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateMintRateLimitWindow(_mintRateLimitWindow);

    currentMintWindowStart = uint48(block.timestamp);
    currentMintWindowMinted = 0;
  }

  /// @notice Updates the maximum number of tokens that can be minted during the rate limit window.
  /// @param _mintRateLimit The new maximum number of tokens that can be minted during the rate limit window.
  function _updateMintRateLimit(uint256 _mintRateLimit) internal {
    emit MintRateLimitUpdated(mintRateLimit, _mintRateLimit);
    mintRateLimit = _mintRateLimit;
  }

  /// @notice Updates the duration of the rate limit window in seconds.
  /// @param _mintRateLimitWindow The new duration of the rate limit window in seconds.
  function _updateMintRateLimitWindow(uint48 _mintRateLimitWindow) internal {
    if (_mintRateLimitWindow == 0) {
      revert ZkMinterRateLimiterV1__InvalidMintRateLimitWindow();
    }
    emit MintRateLimitWindowUpdated(mintRateLimitWindow, _mintRateLimitWindow);
    mintRateLimitWindow = _mintRateLimitWindow;
  }

  /// @notice Reverts if the rate limit is exceeded.
  /// @param _amount The amount of tokens that will be minted.
  function _revertIfRateLimitPerMintWindowExceeded(uint256 _amount) internal view {
    if (currentMintWindowMinted + _amount > mintRateLimit) {
      revert ZkMinterRateLimiterV1__MintRateLimitExceeded(msg.sender, _amount);
    }
  }
}
