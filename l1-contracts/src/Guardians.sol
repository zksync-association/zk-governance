// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IGuardians} from "./interfaces/IGuardians.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";
import {Multisig} from "./Multisig.sol";

/// @title Security Council
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev Temporary protector of the values of zkSync. Approves the changes to the changes proposed by the Token Assembly.
contract Guardians is IGuardians, Multisig, EIP712 {
    /// @notice Address of the contract, which manages protocol upgrades.
    IProtocolUpgradeHandler public immutable protocolUpgradeHandler;

    /// @dev EIP-712 TypeHash for protocol upgrades approval by the guardians.
    bytes32 private constant APPROVE_UPGRADE_GUARDIANS_TYPEHASH = keccak256("ApproveUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for veto by the guardians.
    bytes32 private constant VETO_TYPEHASH = keccak256("Veto(bytes32 id)");

    /// @dev EIP-712 TypeHash for refraining from the veto by the guardians.
    bytes32 private constant REFRAIN_FROM_VETO_TYPEHASH = keccak256("RefrainFromVeto(bytes32 id)");

    /// @dev Initializes the Guardians contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the guardians. 
    /// Expected to be sorted in ascending order without duplicates.
    constructor(IProtocolUpgradeHandler _protocolUpgradeHandler, address[] memory _members)
        Multisig(_members)
        EIP712("Guardians", "1")
    {
        protocolUpgradeHandler = _protocolUpgradeHandler;
        require(_members.length == 8, "Guardians requires exactly 8 members");
    }

    /// @notice Approves zkSync protocol upgrade, by the 5 out of 8 Guardians approvals.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    function approveUpgradeGuardians(bytes32 _id, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(APPROVE_UPGRADE_GUARDIANS_TYPEHASH, _id)));
        _checkSignatures(digest, _signatures, 5);
        protocolUpgradeHandler.approveUpgradeGuardians(_id);
    }

    /// @notice Vetoes a protocol upgrade proposal.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signatures An array of signatures from the guardians vetoing the upgrade.
    function veto(bytes32 _id, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(VETO_TYPEHASH, _id)));
        _checkSignatures(digest, _signatures, 5);
        protocolUpgradeHandler.veto(_id);
    }

    /// @notice Records the guardians' decision to refrain from vetoing a protocol upgrade proposal.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signatures An array of signatures from the guardians refraining from the veto.
    function refrainFromVeto(bytes32 _id, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(REFRAIN_FROM_VETO_TYPEHASH, _id)));
        _checkSignatures(digest, _signatures, 5);
        protocolUpgradeHandler.refrainFromVeto(_id);
    }
}
