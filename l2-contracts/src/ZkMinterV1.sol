// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";

/// @title ZkMinterV1
/// @author [ScopeLift](https://scopelift.co)
/// @notice A base contract with the shared functionality for all ZK Minters.
/// @custom:security-contact security@matterlabs.dev
abstract contract ZkMinterV1 is IMintable, AccessControl, Pausable {
  /// @notice A contract used as a target when calling mint.
  /// @dev Any contract that conforms to the IMintable interface can be used, but in most cases this will be another
  /// `ZKMinter` extension or `ZKCappedMinter`.
  IMintable public mintable;

  /// @notice Whether the contract has been permanently closed.
  bool public closed;

  /// @notice The unique identifier constant used to represent the minter role. An address that has this role may call
  /// the `mint` method, creating new tokens and assigning them to specified address. This role may be granted or
  /// revoked by the DEFAULT_ADMIN_ROLE.
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  /// @notice The unique identifier constant used to represent the pauser role. An address that has this role may call
  /// the `pause` method, pausing all minting operations. This role may be granted or revoked by the DEFAULT_ADMIN_ROLE.
  bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

  /// @notice Emitted when the contract is closed.
  event Closed(address closer);

  /// @notice Emitted when tokens are minted.
  event Minted(address indexed minter, address indexed to, uint256 amount);

  /// @notice Emitted when the mintable contract is updated.
  event MintableUpdated(IMintable indexed previousMintable, IMintable indexed newMintable);

  /// @notice Error for when the contract is closed.
  error ZkMinter__ContractClosed();

  /// @notice Pauses token minting
  function pause() external virtual {
    _checkRole(PAUSER_ROLE, msg.sender);
    _pause();
  }

  /// @notice Unpauses token minting
  function unpause() external virtual {
    _checkRole(PAUSER_ROLE, msg.sender);
    _unpause();
  }

  /// @notice Permanently closes the contract, preventing any future minting.
  /// @dev Once closed, the contract cannot be reopened and all minting operations will be permanently blocked.
  /// @dev Only callable by the admin.
  function close() external virtual {
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    closed = true;
    emit Closed(msg.sender);
  }

  /// @notice Updates the mintable contract that this rate limiter will use for minting.
  /// @param _mintable The new mintable contract to use.
  /// @dev Only callable by addresses with the DEFAULT_ADMIN_ROLE.
  function updateMintable(IMintable _mintable) external virtual {
    _revertIfClosed();
    _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _updateMintable(_mintable);
  }

  /// @notice Updates the mintable contract that this rate limiter will use for minting.
  /// @param _mintable The new mintable contract to use.
  function _updateMintable(IMintable _mintable) internal virtual {
    emit MintableUpdated(mintable, _mintable);
    mintable = _mintable;
  }

  /// @notice Reverts if the contract is closed.
  function _revertIfClosed() internal view virtual {
    if (closed) {
      revert ZkMinter__ContractClosed();
    }
  }
}
