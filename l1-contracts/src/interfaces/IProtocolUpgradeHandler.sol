// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IProtocolUpgradeHandler {
    /// @notice Thrown when a required contract address has no code deployed.
    /// @param contractAddress The address that should be a contract but has no code.
    error EmptyContract(address contractAddress);

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

    /// @dev Parameters controlling which chains and contracts are affected during freeze/unfreeze operations.
    /// @param chainIds The array of chain IDs to affect. Ignored when affectAllChains is true.
    ///        May be empty when affectAllChains is false, e.g. to only affect bridges without touching any chains.
    /// @param affectAllChains If true, all chains registered in the Bridgehub are affected and chainIds must be empty.
    ///        Set to false to affect only specific chains, e.g. to skip misbehaving chains that would cause
    ///        a full-ecosystem operation to run out of gas.
    /// @param affectBridges If true, the bridging contracts (BridgeHub, L1Nullifier, L1AssetRouter,
    ///        L1NativeTokenVault, ChainAssetHandler) are paused or unpaused depending on the calling context.
    struct FreezeParams {
        uint256[] chainIds;
        bool affectAllChains;
        bool affectBridges;
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

    /// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function executeEmergencyUpgrade(
        UpgradeProposal calldata _proposal,
        FreezeParams calldata _params
    ) external payable;

    /// @notice Initiates a soft protocol freeze.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function softFreeze(FreezeParams calldata _params) external;

    /// @notice Initiates a hard protocol freeze.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function hardFreeze(FreezeParams calldata _params) external;

    /// @notice Reinforces the freezing state of the protocol if it is already within the frozen period.
    /// @dev Callable by anyone to allow freezing additional chains when the protocol is already frozen.
    ///      Useful when specific chains are misbehaving after the initial freeze.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function reinforceFreeze(FreezeParams calldata _params) external;

    /// @notice Unfreezes the protocol and resumes normal operations.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function unfreeze(FreezeParams calldata _params) external;

    /// @notice Reinforces the unfreeze for protocol if it is not in the freeze mode.
    /// @dev Callable by anyone to allow unfreezing chains that were left frozen after the main unfreeze.
    ///      Useful when specific chains remained frozen due to misbehavior during the unfreeze operation.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function reinforceUnfreeze(FreezeParams calldata _params) external;

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
    /// @param _protocolFrozenUntil The timestamp until which the protocol is frozen.
    /// @param _params The freeze parameters that were applied.
    event SoftFreeze(uint256 _protocolFrozenUntil, FreezeParams _params);

    /// @notice Emitted when the protocol became hard frozen.
    /// @param _protocolFrozenUntil The timestamp until which the protocol is frozen.
    /// @param _params The freeze parameters that were applied.
    event HardFreeze(uint256 _protocolFrozenUntil, FreezeParams _params);

    /// @notice Emitted when the protocol freeze is reinforced while already frozen.
    /// @param _params The freeze parameters that were applied.
    event ReinforceFreeze(FreezeParams _params);

    /// @notice Emitted when the protocol became active after the soft/hard freeze.
    /// @param _params The unfreeze parameters that were applied.
    event Unfreeze(FreezeParams _params);

    /// @notice Emitted when the protocol unfreeze is reinforced while already unfrozen.
    /// @param _params The unfreeze parameters that were applied.
    event ReinforceUnfreeze(FreezeParams _params);

    /// @notice Emitted when a chain is skipped during freeze/unfreeze because it has no chain type manager.
    /// @param _chainId The chain ID that was skipped.
    event ChainSkippedNoChainTypeManager(uint256 _chainId);
}
