// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {ProtocolUpgradeHandler} from "./ProtocolUpgradeHandler.sol";
import {IChainTypeManager} from "./interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "./interfaces/IBridgeHub.sol";
import {IPausable} from "./interfaces/IPausable.sol";
import {IChainAssetHandler} from "./interfaces/IChainAssetHandler.sol";

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

  /// @notice Initializes the contract with the Security Council address, guardians address and address of L2 voting
  /// governor.
  /// @param _l2ProtocolGovernor The address of the L2 voting governor contract for protocol upgrades.
  /// @param _eraChainTypeManager The address of the Era chain type manager.
  /// @param _zksyncOSChainTypeManager The address of the ZKsync OS chain type manager.
  /// @param _bridgeHub The address of the bridgehub.
  /// @param _l1Nullifier The address of the nullifier
  /// @param _l1AssetRouter The address of the L1 asset router.
  /// @param _l1NativeTokenVault The address of the L1 native token vault.
  /// @param _chainAssetHandler The address of the L1 chain asset handler.
  /// @param _eraChainId The chain ID of ZKsync Era.
  constructor(
    address _l2ProtocolGovernor,
    IChainTypeManager _eraChainTypeManager,
    IChainTypeManager _zksyncOSChainTypeManager,
    IBridgeHub _bridgeHub,
    IPausable _l1Nullifier,
    IPausable _l1AssetRouter,
    IPausable _l1NativeTokenVault,
    IChainAssetHandler _chainAssetHandler,
    uint256 _eraChainId
  )
    ProtocolUpgradeHandler(
      _l2ProtocolGovernor,
      _eraChainTypeManager,
      _zksyncOSChainTypeManager,
      _bridgeHub,
      _l1Nullifier,
      _l1AssetRouter,
      _l1NativeTokenVault,
      _chainAssetHandler,
      _eraChainId
    )
  {}
}
