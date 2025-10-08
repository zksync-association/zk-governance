// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV2} from "src/ZkTokenV2.sol";

/// @title ZkTokenV3
/// @author [ScopeLift](https://scopelift.co)
/// @notice A proxy-upgradeable governance token with minting and burning capability gated by access controls.
/// @dev This contract introduces new functionality for burning tokens. It allows the caller to burn their own tokens
/// using the `burn` function and enables addresses with the burner role to burn tokens from other specified addresses
/// using the `burnFrom` function.
/// @dev The same incrementing nonce is used in `delegateBySig`/`delegateOnBehalf` and `permit` function. If a client is
/// calling these functions one after the other then they should use an incremented nonce for the subsequent call.
/// @custom:security-contact security@zksync.io
contract ZkTokenV3 is ZkTokenV2 {
  /// @notice Constructor that disables initializers to prevent the implementation contract from being initialized.
  constructor() {
    _disableInitializers();
  }

  /// @notice Destroys tokens held by the caller and removes them from the total supply.
  /// @param _amount The quantity of tokens, in raw decimals, that will be destroyed.
  /// @dev The caller must have sufficient balance to burn the requested amount.
  function burn(uint256 _amount) external {
    _burn(msg.sender, _amount);
  }

  /// @notice Destroys tokens held by a given address and removes them from the total supply.
  /// @param _from The address from which tokens will be removed and destroyed.
  /// @param _amount The quantity of tokens, in raw decimals, that will be destroyed.
  /// @dev This method may only be called by an address that has been assigned the burner role by the burner role
  /// admin.
  function burnFrom(address _from, uint256 _amount) external onlyRole(BURNER_ROLE) {
    _burn(_from, _amount);
  }
}
