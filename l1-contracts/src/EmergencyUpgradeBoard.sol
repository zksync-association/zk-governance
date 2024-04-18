// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";

/// @title Emergency Upgrade Board
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract EmergencyUpgradeBoard is EIP712 {
    using SignatureChecker for address;

    /// @notice Address of the contract, which manages protocol upgrades.
    IProtocolUpgradeHandler public immutable PROTOCOL_UPGRADE_HANDLER;

    /// @notice The address of the Security Council.
    address public immutable SECURITY_COUNCIL;

    /// @notice The address of the guardians.
    address public immutable GUARDIANS;

    /// @notice The address of the ZK association multisig.
    address public immutable ZK_ASSOCIATION_SAFE;

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the guardians.
    bytes32 private constant EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH =
        keccak256("ExecuteEmergencyUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the Security Council.
    bytes32 private constant EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
        keccak256("ExecuteEmergencyUpgradeSecurityCouncil(bytes32 id)");

    /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the ZK Association.
    bytes32 private constant EXECUTE_EMERGENCY_UPGRADE_ZK_ASSOCIATION_TYPEHASH =
        keccak256("ExecuteEmergencyUpgradeZKAssociation(bytes32 id)");

    /// @dev Initializes the Emergency Upgrade Board contract with setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _securityCouncil The address of the Security Council multisig.
    /// @param _guardians The address of the Guardians multisig.
    /// @param _zkAssociation The address of the ZK Association Safe multisig.
    constructor(
        IProtocolUpgradeHandler _protocolUpgradeHandler,
        address _securityCouncil,
        address _guardians,
        address _zkAssociation
    ) EIP712("EmergencyUpgradeBoard", "1") {
        PROTOCOL_UPGRADE_HANDLER = _protocolUpgradeHandler;
        SECURITY_COUNCIL = _securityCouncil;
        GUARDIANS = _guardians;
        ZK_ASSOCIATION_SAFE = _zkAssociation;
    }

    /// @notice Executes an emergency protocol upgrade approved by the Security Council, Guardians and ZK association.
    function executeEmergencyUpgrade(
        IProtocolUpgradeHandler.Call[] calldata _calls,
        bytes32 _salt,
        bytes calldata _guardiansSignatures,
        bytes calldata _securityCouncilSignatures,
        bytes calldata _zkAssociationSignatures
    ) external {
        IProtocolUpgradeHandler.UpgradeProposal memory upgradeProposal =
            IProtocolUpgradeHandler.UpgradeProposal({calls: _calls, salt: _salt, executor: address(this)});
        bytes32 id = keccak256(abi.encode(upgradeProposal));

        bytes32 guardiansDigest =
            _hashTypedDataV4(keccak256(abi.encode(EXECUTE_EMERGENCY_UPGRADE_GUARDIANS_TYPEHASH, id)));
        require(GUARDIANS.isValidSignatureNow(guardiansDigest, _guardiansSignatures), "Invalid guardians signatures");

        bytes32 securityCouncilDigest =
            _hashTypedDataV4(keccak256(abi.encode(EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH, id)));
        require(
            SECURITY_COUNCIL.isValidSignatureNow(securityCouncilDigest, _securityCouncilSignatures),
            "Invalid Security Council signatures"
        );

        bytes32 zkAssociationDigest =
            _hashTypedDataV4(keccak256(abi.encode(EXECUTE_EMERGENCY_UPGRADE_ZK_ASSOCIATION_TYPEHASH, id)));
        require(
            ZK_ASSOCIATION_SAFE.isValidSignatureNow(zkAssociationDigest, _zkAssociationSignatures),
            "Invalid ZK association signatures"
        );

        PROTOCOL_UPGRADE_HANDLER.executeEmergencyUpgrade(upgradeProposal);
    }
}
