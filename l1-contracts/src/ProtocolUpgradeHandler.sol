// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IZkSyncEra} from "./interfaces/IZkSyncEra.sol";
import {IStateTransitionManager} from "./interfaces/IStateTransitionManager.sol";
import {IPausable} from "./interfaces/IPausable.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";

/// @title Protocol Upgrade Handler
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev The contract that holds ownership of all zkSync contracts (L1 and L2). It is responsible
/// for handling zkSync protocol upgrades proposed by L2 Token Assembly and executing it.
///
/// The upgrade process follows these key stages:
/// 1. Proposal: Token holders on L2 propose the protocol upgrades and send the L2 -> L1 message
///    that this contract reads and starts the upgrade process.
/// 2. Approval: Requires approval from either the guardians or the Security Council. The Security Council can
///    immediately move the proposal to the next stage, while guardian approval will move the proposal to the
///    next stage only after 90 days delay. If no approval is received within the specified period, the proposal
///    is canceled.
/// 3. Veto Period: During this period, the guardians can veto the upgrade. If the veto period (3 days) expires
///    without intervention, the proposal moves to pending. Guardians can also explicitly refrain
///    from the veto and then the proposal instantly moves to the next stage (pending).
/// 4. Pending: A mandatory delay period before the actual execution of the upgrade, allowing for final
///    preparations and reviews.
/// 5. Execution: The proposed changes are executed by the authorized in the proposal address,
///    completing the upgrade process.
///
/// The contract implements the state machine that represents the logic of moving upgrade from each
/// stage by time changes and Guardians/Security Council actions.
contract ProtocolUpgradeHandler is IProtocolUpgradeHandler {
    /// @dev Specifies the duration of the veto period for guardians.
    /// During this time, guardians have the opportunity to veto proposed upgrades,
    /// providing a safeguard against potentially harmful changes.
    uint256 constant GUARDIANS_VETO_PERIOD = 3 days;

    /// @dev The mandatory delay period before an upgrade can be executed.
    /// This period is intended to provide a buffer after an upgrade's final approval and before its execution,
    /// allowing for final reviews and preparations for devs and users.
    uint256 constant UPGRADE_DELAY_PERIOD = 1 days;

    /// @dev Time limit for an upgrade proposal to be approved or expire, and the waiting period for execution post-guardian approval.
    /// If the Security Council approves, the upgrade can proceed immediately; otherwise,
    /// the proposal will expire after this period if not approved, or wait this period after guardian approval.
    uint256 constant UPGRADE_WAIT_OR_EXPIRE_PERIOD = 90 days;

    /// @dev Duration of a soft freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to decide whether they want to
    /// do hard freeze and protocol upgrade.
    uint256 constant SOFT_FREEZE_PERIOD = 12 hours;

    /// @dev Duration of a hard freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to perform emergency protocol upgrade.
    uint256 constant HARD_FREEZE_PERIOD = 7 days;

    /// @dev Duration of a cooldown period after the soft freeze happen.
    uint256 constant SOFT_FREEZE_COOLDOWN_PERIOD = 3 days;

    /// @dev Duration of a cooldown period after the hard freeze happen.
    uint256 constant HARD_FREEZE_COOLDOWN_PERIOD = 14 days;

    /// @dev Address of the L2 Protocol Governor contract.
    /// This address is used to interface with governance actions initiated on Layer 2,
    /// specifically for proposing and approving protocol upgrades.
    address immutable L2_PROTOCOL_GOVERNOR;

    /// @dev zkSync smart contract that used to operate with L2 via asynchronous L2 <-> L1 communication.
    IZkSyncEra immutable ZKSYNC_ERA;

    /// @dev zkSync smart contract that is responsible for creating new hyperchains and changing parameters in existent.
    IStateTransitionManager immutable STATE_TRANSITION_MANAGER;

    /// @dev Bridgehub smart contract that is used to operate with L2 via asynchronous L2 <-> L1 communication.
    IPausable immutable BRIDGE_HUB;

    /// @dev The shared bridge that is used for all bridging.
    IPausable immutable SHARED_BRIDGE;

    /// @notice The address of the Security Council.
    address public securityCouncil;

    /// @notice The address of the guardians.
    address public guardians;

    /// @notice The address of the smart contract that can execute protocol emergency upgrade.
    address public emergencyUpgradeBoard;

    /// @notice A mapping to store status of an upgrade process for each upgrade ID.
    mapping(bytes32 upgradeId => UpgradeStatus) public upgradeStatus;

    FreezeStatus public freezeStatus;

    /// @notice Stores the timestamp until which the protocol remains frozen.
    uint256 protocolFrozenUntil;

    /// @notice Stores the timestamp until which the protocol can't become frozen for short time.
    uint256 softFreezeCooldownUntil;

    /// @notice Stores the timestamp until which the protocol can't become frozen for long time.
    uint256 hardFreezeCooldownUntil;

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _securityCouncil The address to be assigned as the Security Council of the contract.
    /// @param _guardians The address to be assigned as the guardians of the contract.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    constructor(
        address _securityCouncil,
        address _guardians,
        address _emergencyUpgradeBoard,
        address _l2ProtocolGovernor,
        IZkSyncEra _zkSyncEra,
        IStateTransitionManager _stateTransitionManager,
        IPausable _bridgeHub,
        IPausable _sharedBridge
    ) {
        securityCouncil = _securityCouncil;
        emit ChangeSecurityCouncil(address(0), _securityCouncil);

        guardians = _guardians;
        emit ChangeGuardians(address(0), _guardians);

        emergencyUpgradeBoard = _emergencyUpgradeBoard;
        emit ChangeEmergencyUpgradeBoard(address(0), _emergencyUpgradeBoard);

        L2_PROTOCOL_GOVERNOR = _l2ProtocolGovernor;
        ZKSYNC_ERA = _zkSyncEra;
        STATE_TRANSITION_MANAGER = _stateTransitionManager;
        BRIDGE_HUB = _bridgeHub;
        SHARED_BRIDGE = _sharedBridge;
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks that the message sender is contract itself.
    modifier onlySelf() {
        require(msg.sender == address(this), "Only upgrade handler contract itself is allowed to call this function");
        _;
    }

    /// @notice Checks that the message sender is an active Security Council.
    modifier onlySecurityCouncil() {
        require(msg.sender == securityCouncil, "Only Security Council is allowed to call this function");
        _;
    }

    /// @notice Checks that the message sender is an active guardians.
    modifier onlyGuardians() {
        require(msg.sender == guardians, "Only guardians is allowed to call this function");
        _;
    }

    /// @notice Checks that the message sender is an active Security Council or the protocol is not in freeze.
    modifier onlySecurityCouncilOrProtocolUnfrozen() {
        require(
            msg.sender == securityCouncil || block.timestamp > protocolFrozenUntil,
            "Only Security Council is allowed to call this function or the protocol should be frozen"
        );
        _;
    }

    /// @notice Checks that the message sender is an Emergency Upgrade Board.
    modifier onlyEmergencyUpgradeBoard() {
        require(msg.sender == emergencyUpgradeBoard, "Only Emergency Upgrade Board is allowed to call this function");
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE PROCESS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates the upgrade process by verifying an L2 voting decision.
    /// @dev This function decodes and validates an upgrade proposal message from L2, setting the initial state for the upgrade process.
    /// @param _l2BatchNumber The batch number of the L2 transaction containing the upgrade proposal.
    /// @param _l2MessageIndex The index of the message within the L2 batch.
    /// @param _l2TxNumberInBatch The transaction number of the upgrade proposal in the L2 batch.
    /// @param _proof Merkle proof verifying the inclusion of the upgrade message in the L2 batch.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    function startUpgrade(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _proof,
        UpgradeProposal calldata _proposal
    ) external {
        bytes memory upgradeMessage = abi.encode(_proposal);
        IZkSyncEra.L2Message memory l2ToL1Message = IZkSyncEra.L2Message({
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_PROTOCOL_GOVERNOR,
            data: upgradeMessage
        });
        bool success = ZKSYNC_ERA.proveL2MessageInclusion(_l2BatchNumber, _l2MessageIndex, l2ToL1Message, _proof);
        require(success, "Failed to check upgrade proposal initiation");
        require(_proposal.executor != emergencyUpgradeBoard, "Emergency Upgrade Board can't execute usual upgrade");

        bytes32 id = keccak256(upgradeMessage);
        UpgradeStatus memory upgStatus = upgradeStatus[id];
        require(upgStatus.state == UpgradeState.None, "Upgrade with this id already exists");
        UpgradeStatus memory newUpgStatus =
            UpgradeStatus({state: UpgradeState.Waiting, timestamp: uint48(block.timestamp), guardiansApproval: false});

        upgradeStatus[id] = newUpgStatus;
        emit UpgradeStarted(id, _proposal);
        emit UpgradeStatusChanged(id, newUpgStatus);
    }

    /// @notice Approves an upgrade proposal by the Security Council.
    /// @dev Transitions the state of an upgrade proposal to 'VetoPeriod' after approval by the Security Council.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    function approveUpgradeSecurityCouncil(bytes32 _id) external onlySecurityCouncil {
        UpgradeStatus memory upgStatus = updateUpgradeStatus(_id);
        require(
            upgStatus.state == UpgradeState.Waiting,
            "Upgrade with this id is not waiting for the approval from Security Council"
        );
        UpgradeStatus memory newUpgStatus = UpgradeStatus({
            state: UpgradeState.VetoPeriod,
            timestamp: uint48(block.timestamp),
            guardiansApproval: upgStatus.guardiansApproval
        });
        upgradeStatus[_id] = newUpgStatus;

        emit UpgradeApprovedBySecurityCouncil(_id);
        emit UpgradeStatusChanged(_id, newUpgStatus);
    }

    /// @notice Approves an upgrade proposal by the guardians.
    /// @dev Marks the upgrade proposal identified by `_id` as approved by guardians.
    /// @param _id The unique identifier of the upgrade proposal to approve.
    function approveUpgradeGuardians(bytes32 _id) external onlyGuardians {
        require(!upgradeStatus[_id].guardiansApproval, "Upgrade is already approved by guardians");

        UpgradeStatus memory upgStatus = updateUpgradeStatus(_id);
        require(
            upgStatus.state == UpgradeState.Waiting,
            "Upgrade with this id is not waiting for the approval from Guardians"
        );
        UpgradeStatus memory newUpgStatus =
            UpgradeStatus({state: upgStatus.state, timestamp: uint48(upgStatus.timestamp), guardiansApproval: true});
        upgradeStatus[_id] = newUpgStatus;

        emit UpgradeApprovedByGuardians(_id);
        emit UpgradeStatusChanged(_id, newUpgStatus);
    }

    /// @notice Vetoes an upgrade proposal during its veto period by guardians.
    /// @dev Sets the state of an upgrade proposal identified by `_id` to `Canceled` if it is currently
    /// in the `VetoPeriod`.
    /// @param _id The unique identifier of the upgrade proposal to be vetoed.
    function veto(bytes32 _id) external onlyGuardians {
        UpgradeStatus memory upgStatus = updateUpgradeStatus(_id);
        require(upgStatus.state == UpgradeState.VetoPeriod, "Upgrade can't be vetoed in not the veto period");
        UpgradeStatus memory newUpgStatus = UpgradeStatus({
            state: UpgradeState.Canceled,
            timestamp: uint48(block.timestamp),
            guardiansApproval: upgStatus.guardiansApproval
        });
        upgradeStatus[_id] = newUpgStatus;

        emit UpgradeVetoed(_id);
        emit UpgradeStatusChanged(_id, newUpgStatus);
    }

    /// @notice Records guardians' decision to refrain from vetoing an upgrade proposal.
    /// @dev Transitions the upgrade proposal's status to 'ExecutionPending' if guardians decide not to veto it
    /// during the 'VetoPeriod'.
    /// @param _id The unique identifier of the upgrade proposal for which guardians are refraining from vetoing.
    function refrainFromVeto(bytes32 _id) external onlyGuardians {
        UpgradeStatus memory upgStatus = updateUpgradeStatus(_id);
        require(upgStatus.state == UpgradeState.VetoPeriod, "Guardians can't refrain from veto in not the veto period");
        UpgradeStatus memory newUpgStatus = UpgradeStatus({
            state: UpgradeState.ExecutionPending,
            timestamp: uint48(block.timestamp),
            guardiansApproval: upgStatus.guardiansApproval
        });
        upgradeStatus[_id] = newUpgStatus;

        emit GuardiansRefrainFromVeto(_id);
        emit UpgradeStatusChanged(_id, newUpgStatus);
    }

    /// @notice Executes an upgrade proposal that has reached the 'Ready' state.
    /// @param _proposal The upgrade proposal to be executed, containing the target calls and optionally an executor.
    function execute(UpgradeProposal calldata _proposal) external payable {
        bytes32 id = keccak256(abi.encode(_proposal));
        UpgradeStatus memory upgStatus = updateUpgradeStatus(id);
        // 1. Checks
        require(upgStatus.state == UpgradeState.Ready, "Upgrade is not yet ready");
        require(
            _proposal.executor == address(0) || _proposal.executor == msg.sender,
            "msg.sender is not authorised to perform the upgrade"
        );
        // 2. Effects
        UpgradeStatus memory newUpgStatus = UpgradeStatus({
            state: UpgradeState.Done,
            timestamp: uint48(block.timestamp),
            guardiansApproval: upgStatus.guardiansApproval
        });
        upgradeStatus[id] = newUpgStatus;
        // 3. Interactions
        _execute(_proposal.calls);

        emit UpgradeExecuted(id);
        emit UpgradeStatusChanged(id, newUpgStatus);
    }

    /// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    function executeEmergencyUpgrade(UpgradeProposal calldata _proposal) external payable onlyEmergencyUpgradeBoard {
        bytes32 id = keccak256(abi.encode(_proposal));
        UpgradeStatus memory upgStatus = updateUpgradeStatus(id);
        // 1. Checks
        require(upgStatus.state == UpgradeState.None, "Upgrade already exists");
        require(_proposal.executor == msg.sender, "msg.sender is not authorised to perform the upgrade");
        // 2. Effects
        UpgradeStatus memory newUpgStatus = UpgradeStatus({
            state: UpgradeState.Done,
            timestamp: uint48(block.timestamp),
            guardiansApproval: upgStatus.guardiansApproval
        });
        // Save the upgrade process
        upgradeStatus[id] = newUpgStatus;
        // Clear the freeze
        freezeStatus = FreezeStatus.None;
        protocolFrozenUntil = 0;
        softFreezeCooldownUntil = 0;
        hardFreezeCooldownUntil = 0;
        _unfreeze();
        // 3. Interactions
        _execute(_proposal.calls);
        emit EmergencyUpgradeExecuted(id);
        emit UpgradeStatusChanged(id, newUpgStatus);
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE STATUS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates and returns the current status of an upgrade proposal based on time-based conditions.
    /// @dev This function checks the current block.timestamp against the upgrade proposal's timestamp and
    /// the defined periods for transitions between states (Waiting, VetoPeriod, ExecutionPending).
    /// It returns the updated status without modifying the state.
    /// @param _id The unique identifier of the upgrade proposal whose status is being queried.
    /// @return newUpgStatus The current or imminent status of the upgrade proposal, considering the passage of time
    /// and predefined conditions. This may differ from the stored status if conditions for a state transition are met.
    function getUpgradeStatusNow(bytes32 _id) public view returns (UpgradeStatus memory newUpgStatus) {
        UpgradeStatus memory upgStatus = upgradeStatus[_id];
        newUpgStatus = _getUpgradeStatusOneTimeUpdate(upgStatus);

        // Upgrade status can be changed at most twice in a row by the timing reason,
        // so if the status changes once we need to check it a second time.
        if (upgStatus.state != newUpgStatus.state) {
            newUpgStatus = _getUpgradeStatusOneTimeUpdate(newUpgStatus);
        }
    }

    /// @dev Calculates and returns the upgrade status after one stage changes based on timing.
    /// Please note, that there may be multiple (2 at most) stage changes based on timing in a row,
    /// so this function should be called multiple times to know the latest upgrade status.
    /// @param _upgStatus The upgrade status that may change.
    function _getUpgradeStatusOneTimeUpdate(UpgradeStatus memory _upgStatus)
        internal
        view
        returns (UpgradeStatus memory)
    {
        if (_upgStatus.state == UpgradeState.Waiting) {
            if (block.timestamp > _upgStatus.timestamp + UPGRADE_WAIT_OR_EXPIRE_PERIOD) {
                return UpgradeStatus({
                    state: _upgStatus.guardiansApproval ? UpgradeState.ExecutionPending : UpgradeState.Canceled,
                    timestamp: uint48(_upgStatus.timestamp + UPGRADE_WAIT_OR_EXPIRE_PERIOD),
                    guardiansApproval: _upgStatus.guardiansApproval
                });
            }
        } else if (_upgStatus.state == UpgradeState.VetoPeriod) {
            if (block.timestamp > _upgStatus.timestamp + GUARDIANS_VETO_PERIOD) {
                return UpgradeStatus({
                    state: UpgradeState.ExecutionPending,
                    timestamp: uint48(_upgStatus.timestamp + GUARDIANS_VETO_PERIOD),
                    guardiansApproval: _upgStatus.guardiansApproval
                });
            }
        } else if (_upgStatus.state == UpgradeState.ExecutionPending) {
            if (block.timestamp > _upgStatus.timestamp + UPGRADE_DELAY_PERIOD) {
                return UpgradeStatus({
                    state: UpgradeState.Ready,
                    timestamp: uint48(_upgStatus.timestamp + UPGRADE_DELAY_PERIOD),
                    guardiansApproval: _upgStatus.guardiansApproval
                });
            }
        }

        // All other upgrade state changes triggered on an action basis (e.g. `startUpgrade`, `approveUpgradeSecurityCouncil`, etc).
        return _upgStatus;
    }

    /// @notice Updates the stored status of a specified upgrade proposal to reflect the time-based state changes.
    /// @param _id The unique identifier of the upgrade proposal whose status is to be updated.
    /// @return updatedStatus The new status of the upgrade proposal, reflecting any state transitions based on
    /// the current time and previously defined conditions.
    function updateUpgradeStatus(bytes32 _id) public returns (UpgradeStatus memory updatedStatus) {
        updatedStatus = getUpgradeStatusNow(_id);
        upgradeStatus[_id] = updatedStatus;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute an upgrade's calls.
    /// @param _calls The array of calls to be executed.
    function _execute(Call[] calldata _calls) internal {
        for (uint256 i = 0; i < _calls.length; ++i) {
            (bool success, bytes memory returnData) = _calls[i].target.call{value: _calls[i].value}(_calls[i].data);
            if (!success) {
                // Propagate an error if the call fails.
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            FEEZABILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates a soft protocol freeze.
    function softFreeze() external onlySecurityCouncil {
        require(freezeStatus == FreezeStatus.None, "Protocol already frozen");
        require(block.timestamp > softFreezeCooldownUntil, "Can't freeze in the cooldown period");
        softFreezeCooldownUntil = block.timestamp + SOFT_FREEZE_COOLDOWN_PERIOD;
        freezeStatus = FreezeStatus.Soft;
        protocolFrozenUntil = block.timestamp + SOFT_FREEZE_PERIOD;
        _freeze();
        emit SoftFreeze(protocolFrozenUntil);
    }

    /// @notice Initiates a hard protocol freeze.
    function hardFreeze() external onlySecurityCouncil {
        require(freezeStatus != FreezeStatus.Hard, "Protocol can't be hard frozen");
        require(block.timestamp > hardFreezeCooldownUntil, "Can't freeze in the cooldown period");
        hardFreezeCooldownUntil = block.timestamp + HARD_FREEZE_COOLDOWN_PERIOD;
        freezeStatus = FreezeStatus.Hard;
        protocolFrozenUntil = block.timestamp + HARD_FREEZE_PERIOD;
        _freeze();
        emit HardFreeze(protocolFrozenUntil);
    }

    /// @dev Reinforces the freezing state of the protocol if it is already within the frozen period. This function
    /// can be called by anyone to ensure the protocol remains in a frozen state, particularly useful if there is a need
    /// to confirm or re-apply the freeze due to partial or incomplete application during the initial freeze.
    function reinforceFreeze() external {
        require(block.timestamp <= protocolFrozenUntil, "Protocol should be already frozen");
        _freeze();
        emit ReinforceFreeze();
    }

    /// @dev Freeze all zkSync contracts, including bridges, state transition managers and all hyperchains.
    function _freeze() internal {
        uint256[] memory hyperchainIds = STATE_TRANSITION_MANAGER.getAllHyperchainChainIDs();
        uint256 len = hyperchainIds.length;
        for (uint256 i = 0; i < len; i++) {
            try STATE_TRANSITION_MANAGER.freezeChain(hyperchainIds[i]) {} catch {}
        }

        try BRIDGE_HUB.pause() {} catch {}
        try SHARED_BRIDGE.pause() {} catch {}
    }

    /// @dev Unfreezes the protocol and resumes normal operations.
    function unfreeze() external onlySecurityCouncilOrProtocolUnfrozen {
        require(block.timestamp <= protocolFrozenUntil, "Protocol should be already frozen to unfreeze it");
        freezeStatus = FreezeStatus.None;
        protocolFrozenUntil = 0;
        _unfreeze();
        emit Unfreeze();
    }

    /// @dev Reinforces the unfreeze for protocol if it is not in the freeze mode. This function can be called
    /// by anyone to ensure the protocol remains in a unfrozen state, particularly useful if there is a need
    /// to confirm or re-apply the unfreeze due to partial or incomplete application during the initial unfreeze.
    function reinforceUnfreeze() external {
        require(block.timestamp > protocolFrozenUntil, "Protocol should be already unfrozen");
        _unfreeze();
        emit ReinforceUnfreeze();
    }

    /// @dev Unfreeze all zkSync contracts, including bridges, state transition managers and all hyperchains.
    function _unfreeze() internal {
        uint256[] memory hyperchainIds = STATE_TRANSITION_MANAGER.getAllHyperchainChainIDs();
        uint256 len = hyperchainIds.length;
        for (uint256 i = 0; i < len; i++) {
            try STATE_TRANSITION_MANAGER.unfreezeChain(hyperchainIds[i]) {} catch {}
        }

        try BRIDGE_HUB.unpause() {} catch {}
        try SHARED_BRIDGE.unpause() {} catch {}
    }

    /*//////////////////////////////////////////////////////////////
                            SELF UPGRADES
    //////////////////////////////////////////////////////////////*/

    /// @dev Updates the address of the Security Council.
    /// @param _newSecurityCouncil The address of the new Security Council.
    function updateSecurityCouncil(address _newSecurityCouncil) external onlySelf {
        emit ChangeSecurityCouncil(securityCouncil, _newSecurityCouncil);
        securityCouncil = _newSecurityCouncil;
    }

    /// @dev Updates the address of the guardians.
    /// @param _newGuardians The address of the guardians.
    function updateGuardians(address _newGuardians) external onlySelf {
        emit ChangeGuardians(guardians, _newGuardians);
        guardians = _newGuardians;
    }

    /// @dev Updates the address of the emergency upgrade board.
    /// @param _newEmergencyUpgradeBoard The address of the guardians.
    function updateEmergencyUpgradeBoard(address _newEmergencyUpgradeBoard) external onlySelf {
        emit ChangeEmergencyUpgradeBoard(emergencyUpgradeBoard, _newEmergencyUpgradeBoard);
        emergencyUpgradeBoard = _newEmergencyUpgradeBoard;
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    /// @dev Contract might receive/hold ETH as part of the maintenance process.
    receive() external payable {}
}
