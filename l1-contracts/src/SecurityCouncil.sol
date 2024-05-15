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
    bytes32 internal constant APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("ApproveUpgradeSecurityCouncil(bytes32 id)");

    /// @dev EIP-712 TypeHash for soft emergency freeze approval by the security council.
    bytes32 internal constant SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("SoftFreeze(uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for hard emergency freeze approval by the security council.
    bytes32 internal constant HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("HardFreeze(uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for setting threshold for soft freeze approval by the security council.
    bytes32 internal constant SET_SOFT_FREEZE_THRESHOLD_TYPEHASH =
        keccak256("SetSoftFreezeThreshold(uint256 threshold,uint256 nonce,uint256 validUntil)");

    /// @dev EIP-712 TypeHash for unfreezing the protocol upgrade by the security council.
    bytes32 internal constant UNFREEZE_THRESHOLD_TYPEHASH = keccak256("Unfreeze(uint256 nonce,uint256 validUntil)");

    /// @dev The default threshold for soft freeze initiated by the security council.
    uint256 private constant SOFT_FREEZE_CONSERVATIVE_THRESHOLD = 9;

    /// @dev Tracks the unique identifier used in the last successful soft emergency freeze,
    /// to ensure each request is unique.
    uint256 internal softFreezeNonce;

    /// @dev Tracks the unique identifier used in the last successful hard emergency freeze,
    /// to ensure each request is unique.
    uint256 internal hardFreezeNonce;

    /// @dev Tracks the unique identifier used in the last successful setting of the soft freeze threshold,
    /// to ensure each request is unique.
    uint256 internal softFreezeThresholdSettingNonce;

    /// @dev Tracks the unique identifier used in the last successful unfreeze.
    uint256 internal unfreezeNonce;

    /// @dev Represents the number of signatures needed to trigger soft freeze.
    /// This value is automatically reset to 9 after each freeze, but it can be
    /// set by the 9 SC members and requires to be not bigger than 9.
    uint256 internal softFreezeThreshold;

    /// @dev Initializes the Security Council contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the security council.
    /// Expected to be sorted in ascending order without duplicates.
    constructor(IProtocolUpgradeHandler _protocolUpgradeHandler, address[] memory _members)
        Multisig(_members, 9)
        EIP712("SecurityCouncil", "1")
    {
        protocolUpgradeHandler = _protocolUpgradeHandler;
        require(_members.length == 12, "SecurityCouncil requires exactly 12 members");
        softFreezeThreshold = SOFT_FREEZE_CONSERVATIVE_THRESHOLD;
    }

    /// @notice Approves zkSync protocol upgrade, by the 6 out of 12 Security Council approvals.
    /// @param _id Unique identifier of the upgrade proposal to be approved.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the upgrade.
    function approveUpgradeSecurityCouncil(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures)
        external
    {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(APPROVE_UPGRADE_SECURITY_COUNCIL_TYPEHASH, _id)));
        checkSignatures(digest, _signers, _signatures, 6);
        protocolUpgradeHandler.approveUpgradeSecurityCouncil(_id);
    }

    /// @notice Initiates the protocol soft freeze by small threshold of the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    function softFreeze(uint256 _validUntil, address[] calldata _signers, bytes[] calldata _signatures) external {
        require(block.timestamp < _validUntil, "Signature expired");
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(SOFT_FREEZE_SECURITY_COUNCIL_TYPEHASH, softFreezeNonce++, _validUntil))
        );
        checkSignatures(digest, _signers, _signatures, softFreezeThreshold);
        // Reset threshold
        softFreezeThreshold = SOFT_FREEZE_CONSERVATIVE_THRESHOLD;
        protocolUpgradeHandler.softFreeze();
    }

    /// @notice Initiates the protocol hard freeze by small threshold of the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    function hardFreeze(uint256 _validUntil, address[] calldata _signers, bytes[] calldata _signatures) external {
        require(block.timestamp < _validUntil, "Signature expired");
        bytes32 digest = _hashTypedDataV4(
            keccak256(abi.encode(HARD_FREEZE_SECURITY_COUNCIL_TYPEHASH, hardFreezeNonce++, _validUntil))
        );
        checkSignatures(digest, _signers, _signatures, 9);
        protocolUpgradeHandler.hardFreeze();
    }

    /// @notice Initiates the protocol unfreeze by the Security Council members.
    /// @param _validUntil The timestamp until which the signature should remain valid.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from council members approving the freeze.
    function unfreeze(uint256 _validUntil, address[] calldata _signers, bytes[] calldata _signatures) external {
        require(block.timestamp < _validUntil, "Signature expired");
        bytes32 digest =
            _hashTypedDataV4(keccak256(abi.encode(UNFREEZE_THRESHOLD_TYPEHASH, unfreezeNonce++, _validUntil)));
        checkSignatures(digest, _signers, _signatures, 9);
        protocolUpgradeHandler.unfreeze();
    }

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
    ) external {
        require(_threshold > 0, "Threshold is too small");
        require(_threshold <= SOFT_FREEZE_CONSERVATIVE_THRESHOLD, "Threshold is too big");
        require(block.timestamp < _validUntil, "Signature expired");
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SET_SOFT_FREEZE_THRESHOLD_TYPEHASH, _threshold, softFreezeThresholdSettingNonce++, _validUntil
                )
            )
        );
        checkSignatures(digest, _signers, _signatures, SOFT_FREEZE_CONSERVATIVE_THRESHOLD);
        softFreezeThreshold = _threshold;
    }
}