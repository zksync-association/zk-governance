// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ProtocolUpgradeHandler} from "./ProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "./interfaces/IZKsyncEra.sol";
import {IChainTypeManager} from "./interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "./interfaces/IBridgeHub.sol";
import {IPausable} from "./interfaces/IPausable.sol";

/// @title Testnet Protocol Upgrade Handler
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract TestnetProtocolUpgradeHandler is ProtocolUpgradeHandler {
    /// @dev Duration of the standard legal veto period.
    function STANDARD_LEGAL_VETO_PERIOD() internal pure override returns (uint256) {
        return 0 days;
    }

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
        IChainTypeManager _stateTransitionManager,
        IBridgeHub _bridgeHub,
        IPausable _l1Nullifier,
        IPausable _l1AssetRouter,
        IPausable _l1NativeTokenVault
    )
        ProtocolUpgradeHandler(
            _securityCouncil,
            _guardians,
            _emergencyUpgradeBoard,
            _l2ProtocolGovernor,
            _ZKsyncEra,
            _stateTransitionManager,
            _bridgeHub,
            _l1Nullifier,
            _l1AssetRouter,
            _l1NativeTokenVault
        )
    {}
}
