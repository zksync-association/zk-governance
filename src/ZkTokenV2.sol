// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV1} from "src/ZkTokenV1.sol";

/// @title ZkTokenV2
/// @author [ScopeLift](https://scopelift.co)
/// @notice A proxy-upgradeable governance token with minting and burning capability gated by access controls.
/// @dev The same incrementing nonce is used in `delegateBySig`/`delegateOnBehalf` and `permit` function. If a client is
/// calling these functions one after the other then they should use an incremented nonce for the subsequent call.
/// @custom:security-contact security@zksync.io
contract ZkTokenV2 is ZkTokenV1 {
  /// @notice A version-upgrade configuration method designed for ZkTokenV1's transition to ZkTokenV2.
  /// This method is intended to be called as part of the contract upgrade process on mainnet token.
  /// It updates the token's name to "ZKsync".
  function initializeV2() external reinitializer(2) {
    __ERC20_init("ZKsync", "ZK");
    __ERC20Permit_init("ZKsync");
  }
}
