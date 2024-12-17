// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkCappedMinterV2} from "src/ZkCappedMinterV2.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

/// @title ZkCappedMinterV2Factory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy ZkCappedMinterV2 contracts using CREATE2.
contract ZkCappedMinterV2Factory {
  /// @dev Bytecode hash should be updated with the correct value from
  /// ./zkout/ZkCappedMinterV2.sol/ZkCappedMinterV2.json.
  bytes32 public immutable BYTECODE_HASH;

  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /// @notice Emitted when a new ZkCappedMinterV2 is created.
  /// @param minterAddress The address of the newly deployed ZkCappedMinterV2.
  /// @param mintable The contract where tokens will be minted.
  /// @param admin The address authorized to mint tokens.
  /// @param cap The maximum number of tokens that may be minted.
  /// @param startTime The timestamp when minting can begin.
  /// @param expirationTime The timestamp after which minting is no longer allowed.
  event CappedMinterV2Created(
    address indexed minterAddress,
    IMintable mintable,
    address admin,
    uint256 cap,
    uint48 startTime,
    uint48 expirationTime
  );

  /// @notice Deploys a new ZkCappedMinterV2 contract using CREATE2.
  /// @param _mintable The contract where tokens will be minted.
  /// @param _admin The address authorized to mint tokens.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return minterAddress The address of the newly deployed ZkCappedMinterV2.
  function createCappedMinter(
    IMintable _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) external returns (address minterAddress) {
    bytes memory saltArgs = abi.encode(_mintable, _admin, _cap, _startTime, _expirationTime);
    bytes32 salt = _calculateSalt(saltArgs, _saltNonce);
    ZkCappedMinterV2 instance = new ZkCappedMinterV2{salt: salt}(_mintable, _admin, _cap, _startTime, _expirationTime);
    minterAddress = address(instance);

    emit CappedMinterV2Created(minterAddress, _mintable, _admin, _cap, _startTime, _expirationTime);
  }

  /// @notice Computes the address of a ZkCappedMinterV2 deployed via this factory.
  /// @param _mintable The contract where tokens will be minted.
  /// @param _admin The address authorized to mint tokens.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _startTime The timestamp when minting can begin.
  /// @param _expirationTime The timestamp after which minting is no longer allowed.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return addr The address of the ZkCappedMinterV2.
  function getMinter(
    IMintable _mintable,
    address _admin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) external view returns (address addr) {
    bytes memory saltArgs = abi.encode(_mintable, _admin, _cap, _startTime, _expirationTime);
    bytes32 salt = _calculateSalt(saltArgs, _saltNonce);
    addr = L2ContractHelper.computeCreate2Address(
      address(this), salt, BYTECODE_HASH, keccak256(abi.encode(_mintable, _admin, _cap, _startTime, _expirationTime))
    );
  }

  /// @notice Calculates the salt for CREATE2 deployment.
  /// @param _args The encoded arguments for the salt calculation.
  /// @param _saltNonce A user-provided nonce for additional uniqueness.
  /// @return The calculated salt as a bytes32 value.
  function _calculateSalt(bytes memory _args, uint256 _saltNonce) internal view returns (bytes32) {
    return keccak256(abi.encode(_args, block.chainid, _saltNonce));
  }
}
