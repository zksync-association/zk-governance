// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IL2Governor {
    function cancel(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        bytes32 _descriptionHash
    ) external;

    function propose(
        address[] memory _targets,
        uint256[] memory _values,
        bytes[] memory _calldatas,
        string memory _description
    ) external;
}
