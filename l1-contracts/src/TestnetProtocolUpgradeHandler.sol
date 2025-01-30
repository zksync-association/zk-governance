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

    /// @dev Duration of the standard ugprade delay period.
    function UPGRADE_DELAY_PERIOD() internal pure override returns (uint256) {
        return 0 days;
    }

    /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting governor.
    /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
    /// @param _ZKsyncEra The address of the zkSync Era chain, on top of which the `_l2ProtocolGovernor` is deployed.
    /// @param _chainTypeManager The address of the state transition manager.
    /// @param _bridgeHub The address of the bridgehub.
    /// @param _l1Nullifier The address of the nullifier
    /// @param _l1AssetRouter The address of the L1 asset router.
    /// @param _l1NativeTokenVault The address of the L1 native token vault.
    constructor(
        address _l2ProtocolGovernor,
        IZKsyncEra _ZKsyncEra,
        IChainTypeManager _chainTypeManager,
        IBridgeHub _bridgeHub,
        IPausable _l1Nullifier,
        IPausable _l1AssetRouter,
        IPausable _l1NativeTokenVault
    )
        ProtocolUpgradeHandler(
            _l2ProtocolGovernor,
            _ZKsyncEra,
            _chainTypeManager,
            _bridgeHub,
            _l1Nullifier,
            _l1AssetRouter,
            _l1NativeTokenVault
        )
    {}
}
