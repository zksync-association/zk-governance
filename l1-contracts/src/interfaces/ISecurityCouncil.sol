// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IProtocolUpgradeHandler} from "./IProtocolUpgradeHandler.sol";

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface ISecurityCouncil {
    /// @notice Approves ZKsync protocol upgrade.
    /// @param _id Unique identifier of the upgrade proposal to be approved.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the upgrade.
    function approveUpgradeSecurityCouncil(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures)
        external;

    /// @notice Initiates the protocol soft freeze.
    /// @param _params Freeze parameters specifying which chains and bridges to freeze.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    function softFreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    /// @notice Initiates the protocol hard freeze.
    /// @param _params Freeze parameters specifying which chains and bridges to freeze.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    function hardFreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    /// @notice Initiates the protocol unfreeze.
    /// @param _params Unfreeze parameters specifying which chains and bridges to unfreeze.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the unfreeze.
    function unfreeze(
        IProtocolUpgradeHandler.FreezeParams calldata _params,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;

    /// @notice Sets the threshold for triggering a soft freeze.
    /// @param _threshold New threshold for the Security Council members for approving the soft freeze.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the threshold setting.
    function setSoftFreezeThreshold(
        uint256 _threshold,
        uint256 _validUntil,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external;
}
