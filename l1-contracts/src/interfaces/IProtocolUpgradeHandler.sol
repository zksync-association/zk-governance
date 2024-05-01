// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title ProtocolUpgradeHandler contract interface
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IProtocolUpgradeHandler {
    /// @dev This enumeration includes the following states:
    /// @param None Default state, indicating the upgrade has not been set.
    /// @param Waiting The upgrade passed L2 voting process but it is not yet approved for execution.
    /// @param VetoPeriod The upgrade proposal is waiting for the guardians to veto or explicitly refrain from that.
    /// @param ExecutionPending The upgrade proposal is waiting for the delay period before being ready for execution.
    /// @param Ready The upgrade proposal is ready to be executed.
    /// @param Canceled The upgrade proposal was canceled.
    /// @param Done The upgrade has been successfully executed.
    enum UpgradeState {
        None,
        Waiting,
        VetoPeriod,
        ExecutionPending,
        Ready,
        Canceled,
        Done
    }

    /// @dev Represents the status of an upgrade process, including its current state and the last update time.
    /// @param state The current state of the upgrade, indicating its phase in the lifecycle.
    /// @param timestamp The last time (in seconds) the upgrade state was updated.
    struct UpgradeStatus {
        UpgradeState state;
        uint48 timestamp;
        bool guardiansApproval;
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

    /// @dev Defines the structure of an upgrade that executes by Protocol Upgrade Handler.
    /// @param executor The L1 address that is authorized to perform the upgrade execution (if address(0) then anyone).
    /// @param calls An array of `Call` structs, each representing a call to be made during the upgrade execution.
    /// @param salt A bytes32 value used for creating unique upgrade proposal hashes.
    struct UpgradeProposal {
        Call[] calls;
        address executor;
        bytes32 salt;
    }

    /// @dev This enumeration includes the following states:
    /// @param None Default state, indicating the freeze has not been happen.
    /// @param Soft The protocol is frozen for the short time until the Security Council will approve hard freeze
    /// or soft freeze period will pass.
    /// @param Hard The protocol is frozen for the long time until the Security Council will perfrom the protocol
    /// emergency upgrade or hard freeze period will pass.
    enum FreezeStatus {
        None,
        Soft,
        Hard
    }

    function startUpgrade(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _proof,
        UpgradeProposal calldata _proposal
    ) external;

    function approveUpgradeSecurityCouncil(bytes32 _id) external;

    function approveUpgradeGuardians(bytes32 _id) external;

    function veto(bytes32 _id) external;

    function refrainFromVeto(bytes32 _id) external;

    function execute(UpgradeProposal calldata _proposal) external payable;

    function executeEmergencyUpgrade(UpgradeProposal calldata _proposal) external payable;

    function softFreeze() external;

    function hardFreeze() external;

    function reinforceFreeze() external;

    function unfreeze() external;

    /// @notice Emitted when the security council address is changed.
    event ChangeSecurityCouncil(address _securityCouncilBefore, address _securityCouncilAfter);

    /// @notice Emitted when the guardians address is changed.
    event ChangeGuardians(address _guardiansBefore, address _guardiansAfter);

    /// @notice Emitted when the emergency upgrade board address is changed.
    event ChangeEmergencyUpgradeBoard(address _emergencyUpgradeBoardBefore, address _emergencyUpgradeBoardAfter);

    /// @notice Emitted when upgrade process on L1 is started.
    event UpgradeStarted(bytes32 indexed _id, UpgradeProposal _proposal);

    /// @notice Emitted when Security Council approved the upgrade.
    event UpgradeApprovedBySecurityCouncil(bytes32 indexed _id);

    /// @notice Emitted when Guardians approved the upgrade.
    event UpgradeApprovedByGuardians(bytes32 indexed _id);

    /// @notice Emitted when Guardians vetoed the upgrade.
    event UpgradeVetoed(bytes32 indexed _id);

    /// @notice Emitted when Guardians refrain from veto for the upgrade.
    event GuardiansRefrainFromVeto(bytes32 indexed _id);

    /// @notice Emitted when the upgrade is executed.
    event UpgradeExecuted(bytes32 indexed _id);

    /// @notice Emitted when the emergency upgrade is executed.
    event EmergencyUpgradeExecuted(bytes32 indexed _id);

    /// @notice Emitted when the upgrade status is changed.
    event UpgradeStatusChanged(bytes32 indexed _id, UpgradeStatus _upgradeStatus);

    /// @notice Emitted when the protocol became soft frozen.
    event SoftFreeze(uint256 _protocolFrozenUntil);

    /// @notice Emitted when the protocol became hard frozen.
    event HardFreeze(uint256 _protocolFrozenUntil);

    /// @notice Emitted when someone make an attempt to freeze the protocol when it is frozen already.
    event ReinforceFreeze();

    /// @notice Emitted when the protocol became active after the soft/hard freeze.
    event Unfreeze();

    /// @notice Emitted when someone make an attempt to unfreeze the protocol when it is unfrozen already.
    event ReinforceUnfreeze();
}
