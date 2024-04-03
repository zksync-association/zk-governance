// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface ISecurityCouncil {
    function approveUpgradeSecurityCouncil(bytes32 _id, bytes[] calldata _signatures) external;
}
