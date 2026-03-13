// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title Freeze Flags Library
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice Defines flag constants for freeze/unfreeze operations
library FreezeFlags {
    /// @dev Bit 0 of flags: freeze/unfreeze all chains flag.
    /// When set to 1 in freeze context: freeze all chains.
    /// When set to 1 in unfreeze context: unfreeze all chains.
    uint8 internal constant FLAG_ALL_CHAINS = 1;

    /// @dev Bit 1 of flags: affect bridges flag.
    /// When set to 1 in freeze context: pause bridges.
    /// When set to 1 in unfreeze context: unpause bridges.
    uint8 internal constant FLAG_AFFECT_BRIDGES = 2;
}
