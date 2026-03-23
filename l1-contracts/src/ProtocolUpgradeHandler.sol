// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IChainTypeManager} from "./interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "./interfaces/IBridgeHub.sol";
import {IPausable} from "./interfaces/IPausable.sol";
import {IChainAssetHandler} from "./interfaces/IChainAssetHandler.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

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
///
/// **Freeze Mechanism:**
/// The contract supports two levels of freeze state management:
/// 1. **Protocol-level freeze**: Tracked by `lastFreezeStatusInUpgradeCycle` and `protocolFrozenUntil`.
///    This represents the overall freeze state and upgrade cycle phase.
/// 2. **Chain-level freeze**: Individual chains can be frozen/unfrozen independently.
///
/// These two levels are independent by design. When `unfreeze()` is called:
/// - Protocol-level state transitions (e.g., Soft -> AfterSoftFreeze)
/// - `protocolFrozenUntil` is cleared (set to 0)
/// - Only the specified chains are unfrozen (or all chains if flag is set)
///
/// **Partial Freeze Scenario:**
/// It is possible to have chains in different freeze states simultaneously. For example:
/// 1. `softFreeze([chain1, chain2, chain3], false, true)` - freezes three chains
/// 2. `unfreeze([chain1, chain2], false, true)` - unfreezes only two chains
/// Result: chain3 remains frozen even though `protocolFrozenUntil == 0` and
/// `lastFreezeStatusInUpgradeCycle == AfterSoftFreeze`. This is intentional to allow
/// granular control over chain freeze states for handling misbehaving or problematic chains.
contract ProtocolUpgradeHandler is IProtocolUpgradeHandler, Initializable {
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
    function UPGRADE_DELAY_PERIOD() internal pure virtual returns (uint256) {
        return 5 days;
    }

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

    /// @dev Bridgehub smart contract that is used to operate with L2 via asynchronous L2 <-> L1 communication.
    IBridgeHub public immutable BRIDGE_HUB;

    /// @dev The nullifier contract that is used for bridging.
    IPausable public immutable L1_NULLIFIER;

    /// @dev The asset router contract that is used for bridging.
    IPausable public immutable L1_ASSET_ROUTER;

    /// @dev Vault holding L1 native ETH and ERC20 tokens bridged into the ZK chains.
    IPausable public immutable L1_NATIVE_TOKEN_VAULT;

    /// @dev Chain asset handler contract for migration pausing/unpausing.
    IChainAssetHandler public immutable CHAIN_ASSET_HANDLER;

    /// @dev Chain ID of the Era chain.
    uint256 public immutable ERA_CHAIN_ID;    

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
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    /// @param _bridgeHub The address of the bridgehub.
    /// @param _l1Nullifier The address of the nullifier
    /// @param _l1AssetRouter The address of the L1 asset router.
    /// @param _l1NativeTokenVault The address of the L1 native token vault.
    /// @param _chainAssetHandler The address of the L1 chain asset handler.
    /// @param _eraChainId Chain ID corresponding to ZKsync Era
    constructor(
        address _l2ProtocolGovernor,
        IBridgeHub _bridgeHub,
        IPausable _l1Nullifier,
        IPausable _l1AssetRouter,
        IPausable _l1NativeTokenVault,
        IChainAssetHandler _chainAssetHandler,
        uint256 _eraChainId
    ) {
        _disableInitializers();

        // Sanity checks to prevent misconfiguration
        if (address(_bridgeHub).code.length == 0) revert EmptyContract(address(_bridgeHub));
        if (address(_l1Nullifier).code.length == 0) revert EmptyContract(address(_l1Nullifier));
        if (address(_l1AssetRouter).code.length == 0) revert EmptyContract(address(_l1AssetRouter));
        if (address(_l1NativeTokenVault).code.length == 0) revert EmptyContract(address(_l1NativeTokenVault));
        if (address(_chainAssetHandler).code.length == 0) revert EmptyContract(address(_chainAssetHandler));
        require(_eraChainId != 0, "Era chain ID cannot be zero");

        // Soft configuration check for contracts that inherit this contract.
        assert(STANDARD_LEGAL_VETO_PERIOD() <= EXTENDED_LEGAL_VETO_PERIOD);

        L2_PROTOCOL_GOVERNOR = _l2ProtocolGovernor;
        BRIDGE_HUB = _bridgeHub;
        L1_NULLIFIER = _l1Nullifier;
        L1_ASSET_ROUTER = _l1AssetRouter;
        L1_NATIVE_TOKEN_VAULT = _l1NativeTokenVault;
        CHAIN_ASSET_HANDLER = _chainAssetHandler;
        ERA_CHAIN_ID = _eraChainId;
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
            uint256 readyWithSecurityCouncilTimestamp = upg.securityCouncilApprovalTimestamp + UPGRADE_DELAY_PERIOD();
            return block.timestamp >= readyWithSecurityCouncilTimestamp
                ? UpgradeState.Ready
                : UpgradeState.ExecutionPending;
        }

        uint256 waitOrExpiryTimestamp = upg.creationTimestamp + legalVetoTime + UPGRADE_WAIT_OR_EXPIRE_PERIOD;
        if (block.timestamp >= waitOrExpiryTimestamp) {
            if (!upg.guardiansApproval) {
                return UpgradeState.Expired;
            }

            uint256 readyWithGuardiansTimestamp = waitOrExpiryTimestamp + UPGRADE_DELAY_PERIOD();
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
        IBridgeHub.L2Message memory l2ToL1Message =
            IBridgeHub.L2Message({txNumberInBatch: _l2TxNumberInBatch, sender: L2_PROTOCOL_GOVERNOR, data: upgradeMessage});
        bool success =
            BRIDGE_HUB.proveL2MessageInclusion(ERA_CHAIN_ID, _l2BatchNumber, _l2MessageIndex, l2ToL1Message, _proof);
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
    /// @dev This function clears the freeze state and unfreezes the specified chains.
    /// Misbehaving chains can be skipped by not including them in `_params.chainIds`.
    /// @param _proposal The upgrade proposal details including proposed actions and the executor address.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function executeEmergencyUpgrade(
        UpgradeProposal calldata _proposal,
        FreezeParams calldata _params
    ) external payable onlyEmergencyUpgradeBoard {
        bytes32 id = keccak256(abi.encode(_proposal));
        UpgradeState upgState = upgradeState(id);
        // 1. Checks
        require(upgState == UpgradeState.None, "Upgrade already exists");
        require(_proposal.executor == msg.sender, "msg.sender is not authorized to perform the upgrade");
        // 2. Effects
        upgradeStatus[id].executed = true;
        // Clear the freeze state
        lastFreezeStatusInUpgradeCycle = FreezeStatus.None;
        protocolFrozenUntil = 0;
        // 3. Interactions
        _unfreeze(_params);
        _execute(_proposal.calls);
        emit Unfreeze(_params);
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
    /// @dev Sets protocol-level freeze state and freezes specified chains. The `_params.chainIds` field allows
    /// freezing specific chains when `_params.affectAllChains` is false, enabling skipping freeze operations for
    /// specific problematic chains to prevent them from stalling the freeze for the entire ecosystem.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function softFreeze(FreezeParams calldata _params) external onlySecurityCouncil {
        require(lastFreezeStatusInUpgradeCycle == FreezeStatus.None, "Protocol already frozen");
        lastFreezeStatusInUpgradeCycle = FreezeStatus.Soft;
        protocolFrozenUntil = block.timestamp + SOFT_FREEZE_PERIOD;
        _freeze(_params);
        emit SoftFreeze(protocolFrozenUntil, _params);
    }

    /// @notice Initiates a hard protocol freeze.
    /// @dev Sets protocol-level freeze state and freezes specified chains. The `_params.chainIds` field allows
    /// freezing specific chains when `_params.affectAllChains` is false, enabling skipping freeze operations for
    /// specific problematic chains to prevent them from stalling the freeze for the entire ecosystem.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function hardFreeze(FreezeParams calldata _params) external onlySecurityCouncil {
        FreezeStatus freezeStatus = lastFreezeStatusInUpgradeCycle;
        require(
            freezeStatus == FreezeStatus.None || freezeStatus == FreezeStatus.Soft
                || freezeStatus == FreezeStatus.AfterSoftFreeze,
            "Protocol can't be hard frozen"
        );
        lastFreezeStatusInUpgradeCycle = FreezeStatus.Hard;
        protocolFrozenUntil = block.timestamp + HARD_FREEZE_PERIOD;
        _freeze(_params);
        emit HardFreeze(protocolFrozenUntil, _params);
    }

    /// @notice Reinforces the freezing state of the protocol if it is already within the frozen period.
    /// @dev Callable by anyone — this allows any actor to freeze additional chains that may have been missed
    /// or that became problematic after the initial freeze. Note, that since freezing is authorized for the entire 
    /// ecosystem it is okay to make this function public.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function reinforceFreeze(FreezeParams calldata _params) external {
        require(block.timestamp <= protocolFrozenUntil, "Protocol should be already frozen");
        _freeze(_params);
        emit ReinforceFreeze(_params);
    }

    /// @dev Freeze ZKsync contracts, including bridges, state transition managers and ZK Chains.
    /// @param _params Parameters specifying which parts of the ecosystem to freeze.
    function _freeze(FreezeParams calldata _params) internal {
        // Validate parameters to prevent caller confusion
        if (_params.affectAllChains) {
            require(_params.chainIds.length == 0, "Cannot specify chain IDs when freezing all chains");
        }

        // Note, that it is possible that the chain Ids array is empty and `affectAllChains` is false
        // (e.g. the caller wants to freeze bridges only).
        uint256[] memory chainsToFreeze = _params.affectAllChains
            ? BRIDGE_HUB.getAllZKChainChainIDs()
            : _params.chainIds;

        uint256 len = chainsToFreeze.length;
        for (uint256 i = 0; i < len; ++i) {
            address ctm = BRIDGE_HUB.chainTypeManager(chainsToFreeze[i]);
            if (ctm == address(0)) {
                // Skip chains without a CTM instead of reverting to maintain operational resilience
                emit ChainSkippedNoChainTypeManager(chainsToFreeze[i]);
                continue;
            }
            try IChainTypeManager(ctm).freezeChain(chainsToFreeze[i]) {} catch {}
        }

        if (_params.affectBridges) {
            try BRIDGE_HUB.pause() {} catch {}
            try L1_NULLIFIER.pause() {} catch {}
            try L1_ASSET_ROUTER.pause() {} catch {}
            try L1_NATIVE_TOKEN_VAULT.pause() {} catch {}
            try CHAIN_ASSET_HANDLER.pauseMigration() {} catch {}
        }
    }

    /// @notice Unfreezes the protocol and resumes normal operations.
    /// @dev This function clears the protocol-level freeze state (protocolFrozenUntil = 0) and transitions
    /// lastFreezeStatusInUpgradeCycle (e.g., Soft -> AfterSoftFreeze). However, it only unfreezes the
    /// chains specified in `_params.chainIds` (or all chains if `_params.affectAllChains` is true). This means
    /// it is possible to have the protocol-level freeze cleared while some individual chains remain frozen.
    /// This is intentional to allow handling of misbehaving chains that can block the unfreeze operation for the entire ecosystem.
    /// If a chain has been left frozen after the main unfreeze operation, anyone can call `reinforceUnfreeze()` to unfreeze it later.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function unfreeze(FreezeParams calldata _params) external onlySecurityCouncilOrProtocolFreezeExpired {
        // Prevent front-running attack after freeze expiry:
        // After a freeze period expires, anyone can call unfreeze(). Without this check, an attacker could:
        // 1. Call unfreeze() with strategically chosen subset of chains (affectAllChains=false)
        // 2. Consume the one-time state transition (e.g., Soft → AfterSoftFreeze)
        // 3. Set protocolFrozenUntil = 0
        // 4. Leave all unchosen chains frozen
        // After this, unfreeze() can't be called again (would revert with "Unexpected last freeze status").
        // Only reinforceUnfreeze() (callable by anyone) could fix remaining chains.
        // Therefore, non-Security Council callers must use the all-or-nothing behavior.
        if (msg.sender != securityCouncil) {
            require(_params.affectAllChains, "Non-Security Council must unfreeze all chains");
            require(_params.affectBridges, "Non-Security Council must unpause bridges");
        }

        if (lastFreezeStatusInUpgradeCycle == FreezeStatus.Soft) {
            lastFreezeStatusInUpgradeCycle = FreezeStatus.AfterSoftFreeze;
        } else if (lastFreezeStatusInUpgradeCycle == FreezeStatus.Hard) {
            lastFreezeStatusInUpgradeCycle = FreezeStatus.AfterHardFreeze;
        } else {
            revert("Unexpected last freeze status");
        }
        protocolFrozenUntil = 0;
        _unfreeze(_params);
        emit Unfreeze(_params);
    }

    /// @notice Reinforces the unfreeze for protocol if it is not in the freeze mode.
    /// @dev Callable by anyone — since the protocol is already unfrozen, there is no risk of unauthorized
    /// state transitions. This allows any actor to unfreeze chains that were left frozen due to misbehavior
    /// (e.g. running out of gas) during the main unfreeze operation.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function reinforceUnfreeze(FreezeParams calldata _params) external {
        require(protocolFrozenUntil == 0, "Protocol should be already unfrozen");
        _unfreeze(_params);
        emit ReinforceUnfreeze(_params);
    }

    /// @dev Unfreeze ZKsync contracts, including bridges, state transition managers and ZK Chains.
    /// @param _params Parameters specifying which parts of the ecosystem to unfreeze.
    function _unfreeze(FreezeParams calldata _params) internal {
        // Validate parameters to prevent caller confusion
        if (_params.affectAllChains) {
            require(_params.chainIds.length == 0, "Cannot specify chain IDs when unfreezing all chains");
        }

        uint256[] memory chainsToUnfreeze = _params.affectAllChains
            ? BRIDGE_HUB.getAllZKChainChainIDs()
            : _params.chainIds;

        uint256 len = chainsToUnfreeze.length;
        for (uint256 i = 0; i < len; ++i) {
            address ctm = BRIDGE_HUB.chainTypeManager(chainsToUnfreeze[i]);
            if (ctm == address(0)) {
                // Skip chains without a CTM instead of reverting to maintain operational resilience
                emit ChainSkippedNoChainTypeManager(chainsToUnfreeze[i]);
                continue;
            }
            try IChainTypeManager(ctm).unfreezeChain(chainsToUnfreeze[i]) {} catch {}
        }

        if (_params.affectBridges) {
            try BRIDGE_HUB.unpause() {} catch {}
            try L1_NULLIFIER.unpause() {} catch {}
            try L1_ASSET_ROUTER.unpause() {} catch {}
            try L1_NATIVE_TOKEN_VAULT.unpause() {} catch {}
            try CHAIN_ASSET_HANDLER.unpauseMigration() {} catch {}
        }
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

    /*//////////////////////////////////////////////////////////////
                        PROXY INITIALIZER
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _securityCouncil,
        address _guardians,
        address _emergencyUpgradeBoard
    ) external initializer() {
        securityCouncil = _securityCouncil;
        emit ChangeSecurityCouncil(address(0), _securityCouncil);

        guardians = _guardians;
        emit ChangeGuardians(address(0), _guardians);

        emergencyUpgradeBoard = _emergencyUpgradeBoard;
        emit ChangeEmergencyUpgradeBoard(address(0), _emergencyUpgradeBoard);
    }
}
