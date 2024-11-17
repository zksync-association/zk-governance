// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IZKsyncEra} from "./interfaces/IZKsyncEra.sol";
import {IChainTypeManager} from "./interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "./interfaces/IBridgeHub.sol";
import {IPausable} from "./interfaces/IPausable.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";

/// @title Protocol Upgrade Handler
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev The contract that holds ownership of all ZKsync contracts (L1 and L2). It is responsible
/// for handling ZKsync protocol upgrades proposed by L2 Token Assembly and executing it.
///
/// The upgrade process follows these key stages:
/// 1. Proposal: Token holders on L2 propose the protocol upgrades and send the L2 -> L1 message
///    that this contract reads and starts the upgrade process.
/// 2. Legal veto: During this period, the guardians can veto the upgrade **offchain**. The default legal period review
///    takes 3 days but can be extended by guardians onchain for 7 days in total.
/// 3. Approval: Requires approval from either the guardians or the Security Council. The Security Council can
///    immediately move the proposal to the next stage, while guardians approval will move the proposal to the
///    next stage only after 30 days delay after the legal veto passes. If no approval is received within the specified period, the proposal
///    is expired.
/// 4. Pending: A mandatory delay period before the actual execution of the upgrade, allowing for final
///    preparations and reviews.
/// 5. Execution: The proposed changes are executed by the authorized address in the proposal,
///    completing the upgrade process.
///
/// The contract implements the state machine that represents the logic of moving upgrade from each
/// stage by time changes and Guardians/Security Council actions.
contract ProtocolUpgradeHandler is IProtocolUpgradeHandler {
    /// @dev Duration of the standard legal veto period.
    /// Note: this value should not exceed EXTENDED_LEGAL_VETO_PERIOD.
    function STANDARD_LEGAL_VETO_PERIOD() internal pure virtual returns (uint256) {
        return 3 days;
    }

    /// @dev Duration of the extended legal veto period.
    uint256 internal constant EXTENDED_LEGAL_VETO_PERIOD = 7 days;

    /// @dev The mandatory delay period before an upgrade can be executed.
    /// This period is intended to provide a buffer after an upgrade's final approval and before its execution,
    /// allowing for final reviews and preparations for devs and users.
    uint256 internal constant UPGRADE_DELAY_PERIOD = 1 days;

    /// @dev Time limit for an upgrade proposal to be approved by guardians or expire, and the waiting period for execution post-guardians approval.
    /// If the Security Council approves, the upgrade can proceed immediately; otherwise,
    /// the proposal will expire after this period if not approved, or wait this period after guardians approval.
    uint256 internal constant UPGRADE_WAIT_OR_EXPIRE_PERIOD = 30 days;

    /// @dev Duration of a soft freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to decide whether they want to
    /// do hard freeze and protocol upgrade.
    uint256 internal constant SOFT_FREEZE_PERIOD = 12 hours;

    /// @dev Duration of a hard freeze which temporarily pause protocol contract functionality.
    /// This freeze window is needed for the Security Council to perform emergency protocol upgrade.
    uint256 internal constant HARD_FREEZE_PERIOD = 7 days;

    /// @dev Address of the L2 Protocol Governor contract.
    /// This address is used to interface with governance actions initiated on Layer 2,
    /// specifically for proposing and approving protocol upgrades.
    address public immutable L2_PROTOCOL_GOVERNOR;

    /// @dev ZKsync smart contract that used to operate with L2 via asynchronous L2 <-> L1 communication.
    IZKsyncEra public immutable ZKSYNC_ERA;

    /// @dev ZKsync smart contract that is responsible for creating new ZK Chains and changing parameters in existent.
    IChainTypeManager public immutable CHAIN_TYPE_MANAGER;

    /// @dev Bridgehub smart contract that is used to operate with L2 via asynchronous L2 <-> L1 communication.
    IBridgeHub public immutable BRIDGE_HUB;

    /// @dev The nullifier contract that is used for bridging.
    IPausable public immutable L1_NULLIFIER;

    /// @dev The asset router contract that is used for bridging.
    IPausable public immutable L1_ASSET_ROUTER;

    /// @dev Vault holding L1 native ETH and ERC20 tokens bridged into the ZK chains.
    IPausable public immutable L1_NATIVE_TOKEN_VAULT;

    /// @notice The address of the Security Council.
    address public securityCouncil;

    /// @notice The address of the guardians.
    address public guardians;

    /// @notice The address of the smart contract that can execute protocol emergency upgrade.
    address public emergencyUpgradeBoard;

    /// @notice A mapping to store status of an upgrade process for each upgrade ID.
    mapping(bytes32 upgradeId => UpgradeStatus) public upgradeStatus;

    /// @notice Tracks the last freeze type within an upgrade cycle.
    FreezeStatus public lastFreezeStatusInUpgradeCycle;

    /// @notice Stores the timestamp until which the protocol remains frozen.
    uint256 public protocolFrozenUntil;

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _securityCouncil The address to be assigned as the Security Council of the contract.
    /// @param _guardians The address to be assigned as the guardians of the contract.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    constructor(
        address _securityCouncil,
        address _guardians,
        address _emergencyUpgradeBoard,
        address _l2ProtocolGovernor,
        IZKsyncEra _ZKsyncEra,
        IChainTypeManager _chainTypeManager,
        IBridgeHub _bridgeHub,
        IPausable _l1Nullifier,
        IPausable _l1AssetRouter,
        IPausable _l1NativeTokenVault
    ) {
        // Soft configuration check for contracts that inherit this contract.
        assert(STANDARD_LEGAL_VETO_PERIOD() <= EXTENDED_LEGAL_VETO_PERIOD);

        securityCouncil = _securityCouncil;
        emit ChangeSecurityCouncil(address(0), _securityCouncil);

        guardians = _guardians;
        emit ChangeGuardians(address(0), _guardians);

        emergencyUpgradeBoard = _emergencyUpgradeBoard;
        emit ChangeEmergencyUpgradeBoard(address(0), _emergencyUpgradeBoard);

        L2_PROTOCOL_GOVERNOR = _l2ProtocolGovernor;
        ZKSYNC_ERA = _ZKsyncEra;
        CHAIN_TYPE_MANAGER = _chainTypeManager;
        BRIDGE_HUB = _bridgeHub;
        L1_NULLIFIER = _l1Nullifier;
        L1_ASSET_ROUTER = _l1AssetRouter;
        L1_NATIVE_TOKEN_VAULT = _l1NativeTokenVault;
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

    /// @notice Checks that the message sender is an active Security Council or the protocol is frozen but freeze period expired.
    modifier onlySecurityCouncilOrProtocolFreezeExpired() {
        require(
            msg.sender == securityCouncil || (protocolFrozenUntil != 0 && block.timestamp > protocolFrozenUntil),
            "Only Security Council is allowed to call this function or the protocol should be frozen"
        );
        _;
    }

    /// @notice Checks that the message sender is an Emergency Upgrade Board.
    modifier onlyEmergencyUpgradeBoard() {
        require(msg.sender == emergencyUpgradeBoard, "Only Emergency Upgrade Board is allowed to call this function");
        _;
    }

    /// @notice Calculates the current upgrade state for the specified upgrade ID.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    function upgradeState(bytes32 _id) public view returns (UpgradeState) {
        UpgradeStatus memory upg = upgradeStatus[_id];
        // Upgrade already executed
        if (upg.executed) {
            return UpgradeState.Done;
        }

        // Upgrade doesn't exist
        if (upg.creationTimestamp == 0) {
            return UpgradeState.None;
        }

        // Legal veto period
        uint256 legalVetoTime =
            upg.guardiansExtendedLegalVeto ? EXTENDED_LEGAL_VETO_PERIOD : STANDARD_LEGAL_VETO_PERIOD();
        if (block.timestamp < upg.creationTimestamp + legalVetoTime) {
            return UpgradeState.LegalVetoPeriod;
        }

        // Security council approval case
        if (upg.securityCouncilApprovalTimestamp != 0) {
            uint256 readyWithSecurityCouncilTimestamp = upg.securityCouncilApprovalTimestamp + UPGRADE_DELAY_PERIOD;
            return block.timestamp >= readyWithSecurityCouncilTimestamp
                ? UpgradeState.Ready
                : UpgradeState.ExecutionPending;
        }

        uint256 waitOrExpiryTimestamp = upg.creationTimestamp + legalVetoTime + UPGRADE_WAIT_OR_EXPIRE_PERIOD;
        if (block.timestamp >= waitOrExpiryTimestamp) {
            if (!upg.guardiansApproval) {
                return UpgradeState.Expired;
            }

            uint256 readyWithGuardiansTimestamp = waitOrExpiryTimestamp + UPGRADE_DELAY_PERIOD;
            return block.timestamp >= readyWithGuardiansTimestamp ? UpgradeState.Ready : UpgradeState.ExecutionPending;
        }

        return UpgradeState.Waiting;
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
        IZKsyncEra.L2Message memory l2ToL1Message = IZKsyncEra.L2Message({
            txNumberInBatch: _l2TxNumberInBatch,
            sender: L2_PROTOCOL_GOVERNOR,
            data: upgradeMessage
        });
        bool success = ZKSYNC_ERA.proveL2MessageInclusion(_l2BatchNumber, _l2MessageIndex, l2ToL1Message, _proof);
        require(success, "Failed to check upgrade proposal initiation");
        require(_proposal.executor != emergencyUpgradeBoard, "Emergency Upgrade Board can't execute usual upgrade");

        bytes32 id = keccak256(upgradeMessage);
        UpgradeState upgState = upgradeState(id);
        require(upgState == UpgradeState.None, "Upgrade with this id already exists");

        upgradeStatus[id].creationTimestamp = uint48(block.timestamp);
        emit UpgradeStarted(id, _proposal);
    }

    /// @notice Extends the legal veto period by the guardians.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    function extendLegalVeto(bytes32 _id) external onlyGuardians {
        require(!upgradeStatus[_id].guardiansExtendedLegalVeto, "Legal veto period is already extended");
        UpgradeState upgState = upgradeState(_id);
        require(upgState == UpgradeState.LegalVetoPeriod, "Upgrade with this id is not in the legal veto period");
        upgradeStatus[_id].guardiansExtendedLegalVeto = true;

        emit UpgradeLegalVetoExtended(_id);
    }

    /// @notice Approves an upgrade proposal by the Security Council.
    /// @dev Transitions the state of an upgrade proposal to 'VetoPeriod' after approval by the Security Council.
    /// @param _id The unique identifier of the upgrade proposal to be approved.
    function approveUpgradeSecurityCouncil(bytes32 _id) external onlySecurityCouncil {
        UpgradeState upgState = upgradeState(_id);
        require(
            upgState == UpgradeState.Waiting,
            "Upgrade with this id is not waiting for the approval from Security Council"
        );
        upgradeStatus[_id].securityCouncilApprovalTimestamp = uint48(block.timestamp);

        emit UpgradeApprovedBySecurityCouncil(_id);
    }

    /// @notice Approves an upgrade proposal by the guardians.
    /// @dev Marks the upgrade proposal identified by `_id` as approved by guardians.
    /// @param _id The unique identifier of the upgrade proposal to approve.
    function approveUpgradeGuardians(bytes32 _id) external onlyGuardians {
        require(!upgradeStatus[_id].guardiansApproval, "Upgrade is already approved by guardians");

        UpgradeState upgState = upgradeState(_id);
        require(upgState == UpgradeState.Waiting, "Upgrade with this id is not waiting for the approval from Guardians");
        upgradeStatus[_id].guardiansApproval = true;

        emit UpgradeApprovedByGuardians(_id);
    }

    /// @notice Executes an upgrade proposal that has reached the 'Ready' state.
    /// @param _proposal The upgrade proposal to be executed, containing the target calls and optionally an executor.
    function execute(UpgradeProposal calldata _proposal) external payable {
        bytes32 id = keccak256(abi.encode(_proposal));
        UpgradeState upgState = upgradeState(id);
        // 1. Checks
        require(upgState == UpgradeState.Ready, "Upgrade is not yet ready");
        require(
            _proposal.executor == address(0) || _proposal.executor == msg.sender,
            "msg.sender is not authorized to perform the upgrade"
        );
        // 2. Effects
        upgradeStatus[id].executed = true;
        // 3. Interactions
        _execute(_proposal.calls);
        emit UpgradeExecuted(id);
    }

    /// @notice Executes an emergency upgrade proposal initiated by the emergency upgrade board.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    function executeEmergencyUpgrade(UpgradeProposal calldata _proposal) external payable onlyEmergencyUpgradeBoard {
        bytes32 id = keccak256(abi.encode(_proposal));
        UpgradeState upgState = upgradeState(id);
        // 1. Checks
        require(upgState == UpgradeState.None, "Upgrade already exists");
        require(_proposal.executor == msg.sender, "msg.sender is not authorized to perform the upgrade");
        // 2. Effects
        upgradeStatus[id].executed = true;
        // Clear the freeze
        lastFreezeStatusInUpgradeCycle = FreezeStatus.None;
        protocolFrozenUntil = 0;
        _unfreeze();
        // 3. Interactions
        _execute(_proposal.calls);
        emit Unfreeze();
        emit EmergencyUpgradeExecuted(id);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Execute an upgrade's calls.
    /// @param _calls The array of calls to be executed.
    function _execute(Call[] calldata _calls) internal {
        for (uint256 i = 0; i < _calls.length; ++i) {
            if (_calls[i].data.length > 0) {
                require(
                    _calls[i].target.code.length > 0, "Target must be a smart contract if the calldata is not empty"
                );
            }
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
                            FREEZABILITY
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates a soft protocol freeze.
    function softFreeze() external onlySecurityCouncil {
        require(lastFreezeStatusInUpgradeCycle == FreezeStatus.None, "Protocol already frozen");
        lastFreezeStatusInUpgradeCycle = FreezeStatus.Soft;
        protocolFrozenUntil = block.timestamp + SOFT_FREEZE_PERIOD;
        _freeze();
        emit SoftFreeze(protocolFrozenUntil);
    }

    /// @notice Initiates a hard protocol freeze.
    function hardFreeze() external onlySecurityCouncil {
        FreezeStatus freezeStatus = lastFreezeStatusInUpgradeCycle;
        require(
            freezeStatus == FreezeStatus.None || freezeStatus == FreezeStatus.Soft
                || freezeStatus == FreezeStatus.AfterSoftFreeze,
            "Protocol can't be hard frozen"
        );
        lastFreezeStatusInUpgradeCycle = FreezeStatus.Hard;
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

    /// @dev Reinforces the freezing state of the specific chain if the protocol is already within the frozen period.
    /// The function is an analog of `reinforceFreeze` but only for one specific chain, needed in the
    /// rare case where the execution could get stuck at a particular ID for some unforeseen reason.
    function reinforceFreezeOneChain(uint256 _chainId) external {
        require(block.timestamp <= protocolFrozenUntil, "Protocol should be already frozen");
        CHAIN_TYPE_MANAGER.freezeChain(_chainId);
        emit ReinforceFreezeOneChain(_chainId);
    }

    /// @dev Freeze all ZKsync contracts, including bridges, state transition managers and all ZK Chains.
    function _freeze() internal {
        uint256[] memory zkChainIds = BRIDGE_HUB.getAllZKChainChainIDs();
        uint256 len = zkChainIds.length;
        for (uint256 i = 0; i < len; ++i) {
            try CHAIN_TYPE_MANAGER.freezeChain(zkChainIds[i]) {} catch {}
        }

        try BRIDGE_HUB.pause() {} catch {}
        try L1_NULLIFIER.pause() {} catch {}
        try L1_ASSET_ROUTER.pause() {} catch {}
        try L1_NATIVE_TOKEN_VAULT.pause() {} catch {}
    }

    /// @dev Unfreezes the protocol and resumes normal operations.
    function unfreeze() external onlySecurityCouncilOrProtocolFreezeExpired {
        if (lastFreezeStatusInUpgradeCycle == FreezeStatus.Soft) {
            lastFreezeStatusInUpgradeCycle = FreezeStatus.AfterSoftFreeze;
        } else if (lastFreezeStatusInUpgradeCycle == FreezeStatus.Hard) {
            lastFreezeStatusInUpgradeCycle = FreezeStatus.AfterHardFreeze;
        } else {
            revert("Unexpected last freeze status");
        }
        protocolFrozenUntil = 0;
        _unfreeze();
        emit Unfreeze();
    }

    /// @dev Reinforces the unfreeze for protocol if it is not in the freeze mode. This function can be called
    /// by anyone to ensure the protocol remains in an unfrozen state, particularly useful if there is a need
    /// to confirm or re-apply the unfreeze due to partial or incomplete application during the initial unfreeze.
    function reinforceUnfreeze() external {
        require(protocolFrozenUntil == 0, "Protocol should be already unfrozen");
        _unfreeze();
        emit ReinforceUnfreeze();
    }

    /// @dev Reinforces the unfreeze for one specific chain if the protocol is not in the freeze mode.
    /// The function is an analog of `reinforceUnfreeze` but only for one specific chain, needed in the
    /// rare case where the execution could get stuck at a particular ID for some unforeseen reason.
    function reinforceUnfreezeOneChain(uint256 _chainId) external {
        require(protocolFrozenUntil == 0, "Protocol should be already unfrozen");
        CHAIN_TYPE_MANAGER.unfreezeChain(_chainId);
        emit ReinforceUnfreezeOneChain(_chainId);
    }

    /// @dev Unfreeze all ZKsync contracts, including bridges, state transition managers and all ZK Chains.
    function _unfreeze() internal {
        uint256[] memory zkChainIds = BRIDGE_HUB.getAllZKChainChainIDs();
        uint256 len = zkChainIds.length;
        for (uint256 i = 0; i < len; ++i) {
            try CHAIN_TYPE_MANAGER.unfreezeChain(zkChainIds[i]) {} catch {}
        }

        try BRIDGE_HUB.unpause() {} catch {}
        try L1_NULLIFIER.unpause() {} catch {}
        try L1_ASSET_ROUTER.unpause() {} catch {}
        try L1_NATIVE_TOKEN_VAULT.unpause() {} catch {}
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
