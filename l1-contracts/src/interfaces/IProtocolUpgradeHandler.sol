// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IProtocolUpgradeHandler {
    /// @dev This enumeration includes the following states:
    /// @param None Default state, indicating the upgrade has not been set.
    /// @param LegalVetoPeriod The upgrade passed L2 voting process but it is waiting for the legal veto period.
    /// @param Waiting The upgrade passed Legal Veto period but it is waiting for the approval from guardians or Security Council.
    /// @param ExecutionPending The upgrade proposal is waiting for the delay period before being ready for execution.
    /// @param Ready The upgrade proposal is ready to be executed.
    /// @param Expired The upgrade proposal was expired.
    /// @param Done The upgrade has been successfully executed.
    enum UpgradeState {
        None,
        LegalVetoPeriod,
        Waiting,
        ExecutionPending,
        Ready,
        Expired,
        Done
    }

    /// @dev Represents the status of an upgrade process, including the creation timestamp and actions made by guardians and Security Council.
    /// @param creationTimestamp The timestamp (in seconds) when the upgrade state was created.
    /// @param securityCouncilApprovalTimestamp The timestamp (in seconds) when Security Council approved the upgrade.
    /// @param guardiansApproval Indicates whether the upgrade has been approved by the guardians.
    /// @param guardiansExtendedLegalVeto Indicates whether guardians extended the legal veto period.
    /// @param executed Indicates whether the proposal is executed or not.
    struct UpgradeStatus {
        uint48 creationTimestamp;
        uint48 securityCouncilApprovalTimestamp;
        bool guardiansApproval;
        bool guardiansExtendedLegalVeto;
        bool executed;
    }

    /// @dev Represents a call to be made during an upgrade.
    /// @param target The address to which the call will be made.
    /// @param value The amount of Ether (in wei) to be sent along with the call.
    /// @param data The calldata to be executed on the `target` address.
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /// @dev Defines the structure of an upgrade that is executed by Protocol Upgrade Handler.
    /// @param executor The L1 address that is authorized to perform the upgrade execution (if address(0) then anyone).
    /// @param calls An array of `Call` structs, each representing a call to be made during the upgrade execution.
    /// @param salt A bytes32 value used for creating unique upgrade proposal hashes.
    struct UpgradeProposal {
        Call[] calls;
        address executor;
        bytes32 salt;
    }

    /// @dev This enumeration includes the following states:
    /// @param None Default state, indicating the freeze has not been happening in this upgrade cycle.
    /// @param Soft The protocol is/was frozen for the short time.
    /// @param Hard The protocol is/was frozen for the long time.
    /// @param AfterSoftFreeze The protocol was soft frozen, it can be hard frozen in this upgrade cycle.
    /// @param AfterHardFreeze The protocol was hard frozen, but now it can't be frozen until the upgrade.
    enum FreezeStatus {
        None,
        Soft,
        Hard,
        AfterSoftFreeze,
        AfterHardFreeze
    }

    function startUpgrade(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _proof,
        UpgradeProposal calldata _proposal
    ) external;

    function extendLegalVeto(bytes32 _id) external;

    function approveUpgradeSecurityCouncil(bytes32 _id) external;

    function approveUpgradeGuardians(bytes32 _id) external;

    function execute(UpgradeProposal calldata _proposal) external payable;

    function executeEmergencyUpgrade(UpgradeProposal calldata _proposal) external payable;

    function softFreeze() external;

    function hardFreeze() external;

    function reinforceFreeze() external;

    function unfreeze() external;

    function reinforceFreezeOneChain(uint256 _chainId) external;

    function reinforceUnfreeze() external;

    function reinforceUnfreezeOneChain(uint256 _chainId) external;

    function upgradeState(bytes32 _id) external view returns (UpgradeState);

    function updateSecurityCouncil(address _newSecurityCouncil) external;

    function updateGuardians(address _newGuardians) external;

    function updateEmergencyUpgradeBoard(address _newEmergencyUpgradeBoard) external;

    /// @notice Emitted when the security council address is changed.
    event ChangeSecurityCouncil(address indexed _securityCouncilBefore, address indexed _securityCouncilAfter);

    /// @notice Emitted when the guardians address is changed.
    event ChangeGuardians(address indexed _guardiansBefore, address indexed _guardiansAfter);

    /// @notice Emitted when the emergency upgrade board address is changed.
    event ChangeEmergencyUpgradeBoard(
        address indexed _emergencyUpgradeBoardBefore, address indexed _emergencyUpgradeBoardAfter
    );

    /// @notice Emitted when upgrade process on L1 is started.
    event UpgradeStarted(bytes32 indexed _id, UpgradeProposal _proposal);

    /// @notice Emitted when the legal veto period is extended.
    event UpgradeLegalVetoExtended(bytes32 indexed _id);

    /// @notice Emitted when Security Council approved the upgrade.
    event UpgradeApprovedBySecurityCouncil(bytes32 indexed _id);

    /// @notice Emitted when Guardians approved the upgrade.
    event UpgradeApprovedByGuardians(bytes32 indexed _id);

    /// @notice Emitted when the upgrade is executed.
    event UpgradeExecuted(bytes32 indexed _id);

    /// @notice Emitted when the emergency upgrade is executed.
    event EmergencyUpgradeExecuted(bytes32 indexed _id);

    /// @notice Emitted when the protocol became soft frozen.
    event SoftFreeze(uint256 _protocolFrozenUntil);

    /// @notice Emitted when the protocol became hard frozen.
    event HardFreeze(uint256 _protocolFrozenUntil);

    /// @notice Emitted when someone makes an attempt to freeze the protocol when it is frozen already.
    event ReinforceFreeze();

    /// @notice Emitted when the protocol became active after the soft/hard freeze.
    event Unfreeze();

    /// @notice Emitted when someone makes an attempt to freeze the specific chain when the protocol is frozen already.
    event ReinforceFreezeOneChain(uint256 _chainId);

    /// @notice Emitted when someone makes an attempt to unfreeze the protocol when it is unfrozen already.
    event ReinforceUnfreeze();

    /// @notice Emitted when someone makes an attempt to unfreeze the specific chain when the protocol is unfrozen already.
    event ReinforceUnfreezeOneChain(uint256 _chainId);
}
