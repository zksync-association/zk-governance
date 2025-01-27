// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ProtocolUpgradeHandler} from "./ProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "./interfaces/IZKsyncEra.sol";
import {IStateTransitionManager} from "./interfaces/IStateTransitionManager.sol";
import {IPausable} from "./interfaces/IPausable.sol";

/// @title Testnet Protocol Upgrade Handler
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
contract TestnetProtocolUpgradeHandler is ProtocolUpgradeHandler {
    /// @dev Duration of the standard legal veto period.
    function STANDARD_LEGAL_VETO_PERIOD() internal pure override returns (uint256) {
        return 0 days;
    }

    /// @dev Duration of the standard ugprade delay period.
    function UPGRADE_DELAY_PERIOD() internal pure override returns (uint256) {
        return 0 days;
    }

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    /// @param _ZKsyncEra The address of the zkSync Era chain, on top of which the `_l2ProtocolGovernor` is deployed.
    /// @param _stateTransitionManager The address of the state transition manager.
    /// @param _bridgeHub The address of the bridgehub.
    /// @param _sharedBridge The address of the shared bridge.
    constructor(
        address _l2ProtocolGovernor,
        IZKsyncEra _ZKsyncEra,
        IStateTransitionManager _stateTransitionManager,
        IPausable _bridgeHub,
        IPausable _sharedBridge
    )
        ProtocolUpgradeHandler(
            _l2ProtocolGovernor,
            _ZKsyncEra,
            _stateTransitionManager,
            _bridgeHub,
            _sharedBridge
        )
    {}
}
