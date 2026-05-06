// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IProtocolUpgradeHandler} from "./IProtocolUpgradeHandler.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface ISecurityCouncil {
    function approveUpgradeSecurityCouncil(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures)
        external;

    function softFreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    function hardFreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    function unfreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    function setSoftFreezeThreshold(
        uint256 _threshold,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;
}
