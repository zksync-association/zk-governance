// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IGuardians {
    function approveUpgradeGuardians(bytes32 _id, bytes[] calldata _signatures) external;

    function veto(bytes32 _id, bytes[] calldata _signatures) external;

    function refrainFromVeto(bytes32 _id, bytes[] calldata _signatures) external;
}
