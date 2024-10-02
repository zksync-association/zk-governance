// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {L2ContractHelper} from "src/lib/L2ContractHelper.sol";
import {ZkCappedMinter} from "src/ZkCappedMinter.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";

/// @title ZkCappedMinterFactory
/// @author [ScopeLift](https://scopelift.co)
/// @notice Factory contract to deploy ZkCappedMinter contracts using CREATE2.
contract ZkCappedMinterFactory {
  /// @dev Bytecode hash should be updated with the correct value from ./zkout/ZkCappedMinter.sol/ZkCappedMinter.json.
  bytes32 public immutable BYTECODE_HASH;

  constructor(bytes32 _bytecodeHash) {
    BYTECODE_HASH = _bytecodeHash;
  }

  /// @notice Emitted when a new ZkCappedMinter is created.
  /// @param minterAddress The address of the newly deployed ZkCappedMinter.
  /// @param token The token contract where tokens will be minted.
  /// @param admin The address authorized to mint tokens.
  /// @param cap The maximum number of tokens that may be minted.
  event CappedMinterCreated(address indexed minterAddress, IMintableAndDelegatable token, address admin, uint256 cap);

  /// @notice Deploys a new ZkCappedMinter contract using CREATE2.
  /// @param _token The token contract where tokens will be minted.
  /// @param _admin The address authorized to mint tokens.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _saltNonce A user-provided nonce for salt calculation.
  /// @return minterAddress The address of the newly deployed ZkCappedMinter.
  function createCappedMinter(IMintableAndDelegatable _token, address _admin, uint256 _cap, uint256 _saltNonce)
    external
    returns (address minterAddress)
  {
    bytes memory saltArgs = abi.encode(_token, _admin, _cap);
    bytes32 salt = _calculateSalt(saltArgs, _saltNonce);
    ZkCappedMinter instance = new ZkCappedMinter{salt: salt}(_token, _admin, _cap);
    minterAddress = address(instance);

    emit CappedMinterCreated(minterAddress, _token, _admin, _cap);
  }

  /// @notice Computes the address of a ZkCappedMinter deployed via this factory.
  /// @param _token The token contract where tokens will be minted.
  /// @param _admin The address authorized to mint tokens.
  /// @param _cap The maximum number of tokens that may be minted.
  /// @param _saltNonce The nonce used for salt calculation.
  /// @return addr The address of the ZkCappedMinter.
  function getMinter(IMintableAndDelegatable _token, address _admin, uint256 _cap, uint256 _saltNonce)
    external
    view
    returns (address addr)
  {
    bytes memory saltArgs = abi.encode(_token, _admin, _cap);
    bytes32 salt = _calculateSalt(saltArgs, _saltNonce);
    addr = L2ContractHelper.computeCreate2Address(
      address(this), salt, BYTECODE_HASH, keccak256(abi.encode(_token, _admin, _cap))
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
