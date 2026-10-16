// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @dev Getters of the `ProtocolUpgradeHandler` roles checked by `ProtocolUpgradeHandlerStateCheck`.
interface IProtocolUpgradeHandlerRoles {
  function securityCouncil() external view returns (address);

  function guardians() external view returns (address);

  function emergencyUpgradeBoard() external view returns (address);
}

/// @title Protocol Upgrade Handler State Check
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev Stateless helper meant to be the first call of a protocol upgrade proposal. It pins the governance roles the
/// proposal was built against: if the `ProtocolUpgradeHandler` roles differ from the expected ones (e.g. a preceding
/// upgrade that rotates them has not been executed yet), the call reverts and so does the whole proposal execution.
/// A reverted execution does not mark the proposal as executed, so it can be retried once the expected state is in
/// place.
contract ProtocolUpgradeHandlerStateCheck {
  /// @notice Reverts unless the `ProtocolUpgradeHandler` roles match the expected addresses.
  /// @param _protocolUpgradeHandler The address of the protocol upgrade handler to check.
  /// @param _expectedSecurityCouncil The expected address of the Security Council.
  /// @param _expectedGuardians The expected address of the guardians.
  /// @param _expectedEmergencyUpgradeBoard The expected address of the Emergency Upgrade Board.
  function checkRoles(
    IProtocolUpgradeHandlerRoles _protocolUpgradeHandler,
    address _expectedSecurityCouncil,
    address _expectedGuardians,
    address _expectedEmergencyUpgradeBoard
  ) external view {
    require(_protocolUpgradeHandler.securityCouncil() == _expectedSecurityCouncil, "Unexpected Security Council");
    require(_protocolUpgradeHandler.guardians() == _expectedGuardians, "Unexpected guardians");
    require(
      _protocolUpgradeHandler.emergencyUpgradeBoard() == _expectedEmergencyUpgradeBoard,
      "Unexpected Emergency Upgrade Board"
    );
  }
}
