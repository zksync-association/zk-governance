// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ISecurityCouncil} from "./interfaces/ISecurityCouncil.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";
import {Multisig} from "./Multisig.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title Security Council
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev The group of security experts who serve as a technical security service for zkSync protocol.
contract SecurityCouncil is ISecurityCouncil, Multisig, EIP712 {
    /// @notice Address of the contract, which manages protocol upgrades.
    IProtocolUpgradeHandler public immutable protocolUpgradeHandler;

    /// @dev EIP-712 TypeHash for protocol upgrades approval by the security council.
    bytes32 private constant APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("ApproveUpgradeSecurityCouncil(bytes32 id)");

    /// @dev Initializes the Security Council contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the security council. Expected to be sorted without duplicates.
    constructor(IProtocolUpgradeHandler _protocolUpgradeHandler, address[] memory _members)
        Multisig(_members)
        EIP712("SecurityCouncil", "1")
    {
        protocolUpgradeHandler = _protocolUpgradeHandler;
        require(_members.length == 12, "SecurityCouncil requires exactly 12 members");
    }

    /// @notice Approves zkSync protocol upgrade, by the 6 out of 12 Security Council approvals.
    /// @param _id Unique identifier of the upgrade proposal to be approved.
    /// @param _signatures An array of signatures from council members approving the upgrade.
    function approveUpgradeSecurityCouncil(bytes32 _id, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH, _id)));
        _checkSignatures(digest, _signatures, 6);
        protocolUpgradeHandler.approveUpgradeSecurityCouncil(_id);
    }
}
