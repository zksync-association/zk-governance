// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IChainTypeManager {
    function freezeChain(uint256 _chainId) external;

    function unfreezeChain(uint256 _chainId) external;
}
