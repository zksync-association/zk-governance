// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IStateTransitionManager {
    function freezeChain(uint256 _chainId) external;

    function unfreezeChain(uint256 _chainId) external;

    function getAllHyperchainChainIDs() external view returns (uint256[] memory);
}
