// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkMinterRateLimiterV1} from "src/ZkMinterRateLimiterV1.sol";
import {IZkMinterV1Factory} from "src/interfaces/IZkMinterV1Factory.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkMinterRateLimiterV1Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy `ZkMinterRateLimiterV1` contracts using CREATE2.
/// @custom:security-contact security@matterlabs.dev
contract ZkMinterRateLimiterV1Factory is IZkMinterV1Factory {
  /// @dev Bytecode hash should be updated with the correct value from
  /// ./zkout/ZkMinterRateLimiterV1.sol/ZkMinterRateLimiterV1.json.
  bytes32 public immutable BYTECODE_HASH;

  /// @notice Error thrown when attempting to create a minter rate limiter with a zero address admin.
  error ZkMinterRateLimiterV1Factory__InvalidAdminAddress();

  /// @notice Initializes the factory with the bytecode hash of the ZkMinterRateLimiterV1 contract.
  /// @param _bytecodeHash The bytecode hash of the ZkMinterRateLimiterV1 contract to be used for CREATE2 deployments.
  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

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
  ) external returns (address _minterRateLimiterAddress) {
    _minterRateLimiterAddress = _createMinter(_mintable, _admin, _mintRateLimit, _mintRateLimitWindow, _saltNonce);
  }

  /// @notice Deploys a new `ZkMinterRateLimiterV1` contract using CREATE2. This method takes bytes argument
  /// and is meant to be used in a unified factory for all capped minter extensions.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _args The args to deploy ZkMinterRateLimiterV1.
  /// @return The address of the newly deployed `ZkMinterRateLimiterV1`.
  function createMinter(IMintable _mintable, bytes memory _args) external returns (address) {
    (address _admin, uint256 _mintRateLimit, uint48 _mintRateLimitWindow, uint256 _saltNonce) =
      abi.decode(_args, (address, uint256, uint48, uint256));
    return _createMinter(_mintable, _admin, _mintRateLimit, _mintRateLimitWindow, _saltNonce);
  }

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
  ) external view returns (address _minterRateLimiterAddress) {
    bytes32 salt = _calculateSalt(_saltNonce);
    _minterRateLimiterAddress = L2ContractHelper.computeCreate2Address(
      address(this), salt, BYTECODE_HASH, keccak256(abi.encode(_mintable, _admin, _mintRateLimit, _mintRateLimitWindow))
    );
  }

  /// @notice Calculates the salt for CREATE2 deployment.
  /// @param _saltNonce A user-provided nonce for additional uniqueness.
  /// @return The calculated salt as a bytes32 value.
  function _calculateSalt(uint256 _saltNonce) internal view returns (bytes32) {
    return keccak256(abi.encode(block.chainid, _saltNonce));
  }

  /// @notice Deploys a new `ZkMinterRateLimiterV1` contract using CREATE2.
  /// @param _mintable A contract used as a target when calling mint.
  /// @param _admin The address that will have admin privileges.
  /// @param _mintRateLimit The maximum number of tokens that may be minted within the rate limit window.
  /// @param _mintRateLimitWindow The duration in seconds of the rate limit window.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return _minterRateLimiterAddress The address of the newly deployed `ZkMinterRateLimiterV1`.
  function _createMinter(
    IMintable _mintable,
    address _admin,
    uint256 _mintRateLimit,
    uint48 _mintRateLimitWindow,
    uint256 _saltNonce
  ) internal returns (address _minterRateLimiterAddress) {
    if (_admin == address(0)) {
      revert ZkMinterRateLimiterV1Factory__InvalidAdminAddress();
    }
    bytes32 _salt = _calculateSalt(_saltNonce);

    ZkMinterRateLimiterV1 instance =
      new ZkMinterRateLimiterV1{salt: _salt}(_mintable, _admin, _mintRateLimit, _mintRateLimitWindow);
    _minterRateLimiterAddress = address(instance);

    emit MinterRateLimiterCreated(_minterRateLimiterAddress, _mintable, _admin, _mintRateLimit, _mintRateLimitWindow);
  }
}
