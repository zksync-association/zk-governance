// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {
  ProtocolUpgradeHandlerStateCheck,
  IProtocolUpgradeHandlerRoles
} from "../src/ProtocolUpgradeHandlerStateCheck.sol";

import {MainnetRemoveGuardians} from "../scripts/MainnetRemoveGuardians.s.sol";
import {RemoveGuardiansDeployedContracts} from "../scripts/RemoveGuardians.s.sol";

/// @dev Verifies the guardians removal flow against a mainnet fork (`--fork-url <L1_MAINNET_RPC>`):
/// runs the MainnetRemoveGuardians script, replays the v31 handler upgrade it is built against,
/// passes the generated Call[] through the regular upgrade flow of the ProtocolUpgradeHandler and
/// checks the resulting system state. Only the L2 -> L1 message proof of `startUpgrade` is skipped,
/// the upgrade is registered by writing its creation timestamp directly.
contract RemoveGuardiansForkTest is Test {
  // Must match MainnetRemoveGuardians
  address constant PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;
  address constant V31_SECURITY_COUNCIL = 0x29D2e773A31C07D375c50F0110422832bd044d08;
  address constant V31_GUARDIANS = 0x8f525e55F76050d8dFdDa4870DA1b3ede54E908F;
  address constant V31_EMERGENCY_UPGRADE_BOARD = 0x91989F9BB8391D3471D2672Ec001921cB14C4b7C;

  // v31 (ZIP-18) stage 0: `ProxyAdmin.upgradeAndCall(PUH proxy, newImpl, initialize(...))`, see
  // transaction-simulator decoded-calldata/2026-09-08-v31-interopB-mainnet.json.
  address constant PROTOCOL_UPGRADE_HANDLER_PROXY_ADMIN = 0x1e4c534e7ce1FF5621Ea506D99b367D7d8EFbE3e;
  address constant V31_PROTOCOL_UPGRADE_HANDLER_IMPL = 0x76C4c9897c610C554C948Ece32BEF1257ddE3811;

  // `ProtocolUpgradeHandler.upgradeStatus` mapping slot (`forge inspect ProtocolUpgradeHandler storageLayout`).
  uint256 constant UPGRADE_STATUS_SLOT = 3;
  // Mainnet `STANDARD_LEGAL_VETO_PERIOD` and `UPGRADE_DELAY_PERIOD` of the ProtocolUpgradeHandler.
  uint256 constant LEGAL_VETO_PERIOD = 3 days;
  uint256 constant UPGRADE_DELAY_PERIOD = 9 days;

  MainnetRemoveGuardians script;
  ProtocolUpgradeHandler handler;

  address zkFoundationSafe;
  address newEmergencyUpgradeBoard;
  address stateCheck;

  modifier onlyMainnet() {
    if (block.chainid == 1) {
      _;
    } else {
      return;
    }
  }

  function setUp() external onlyMainnet {
    handler = ProtocolUpgradeHandler(payable(PROTOCOL_UPGRADE_HANDLER));
    zkFoundationSafe = EmergencyUpgradeBoard(V31_EMERGENCY_UPGRADE_BOARD).ZK_FOUNDATION_SAFE();

    // The script only depends on the (already deployed) v31 contracts, so it runs before v31 is executed.
    script = new MainnetRemoveGuardians();
    script.run();

    RemoveGuardiansDeployedContracts memory deployed = script.getDeployedAddresses();
    newEmergencyUpgradeBoard = deployed.emergencyUpgradeBoard;
    stateCheck = deployed.stateCheck;
  }

  /// @dev Replays the v31 upgrade of the ProtocolUpgradeHandler, unless the fork already includes it.
  function _applyV31() internal {
    if (handler.securityCouncil() == V31_SECURITY_COUNCIL) {
      return;
    }
    vm.prank(PROTOCOL_UPGRADE_HANDLER);
    ProxyAdmin(PROTOCOL_UPGRADE_HANDLER_PROXY_ADMIN)
      .upgradeAndCall(
        ITransparentUpgradeableProxy(PROTOCOL_UPGRADE_HANDLER),
        V31_PROTOCOL_UPGRADE_HANDLER_IMPL,
        abi.encodeCall(
          ProtocolUpgradeHandler.initialize, (V31_SECURITY_COUNCIL, V31_GUARDIANS, V31_EMERGENCY_UPGRADE_BOARD)
        )
      );
  }

  function _removeGuardiansProposal() internal view returns (IProtocolUpgradeHandler.UpgradeProposal memory) {
    return IProtocolUpgradeHandler.UpgradeProposal({
      calls: script.getGeneratedCalls(), salt: bytes32(0), executor: address(0)
    });
  }

  /// @dev Registers the proposal as if `startUpgrade` had verified the L2 -> L1 message, then lets the
  /// current Security Council approve it and waits until it is ready.
  function _passUpgrade(IProtocolUpgradeHandler.UpgradeProposal memory _proposal) internal {
    bytes32 id = keccak256(abi.encode(_proposal));
    bytes32 statusSlot = keccak256(abi.encode(id, UPGRADE_STATUS_SLOT));
    // `creationTimestamp` is the lowest packed field of `UpgradeStatus`.
    vm.store(PROTOCOL_UPGRADE_HANDLER, statusSlot, bytes32(block.timestamp));
    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));

    vm.warp(block.timestamp + LEGAL_VETO_PERIOD);
    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));

    vm.prank(handler.securityCouncil());
    handler.approveUpgradeSecurityCouncil(id);

    vm.warp(block.timestamp + UPGRADE_DELAY_PERIOD);
    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Ready));
  }

  function _executeRemoveGuardians() internal {
    _applyV31();
    IProtocolUpgradeHandler.UpgradeProposal memory proposal = _removeGuardiansProposal();
    _passUpgrade(proposal);
    handler.execute(proposal);
  }

  function test_MainnetForkNewBoardConfiguration() external onlyMainnet {
    EmergencyUpgradeBoard newBoard = EmergencyUpgradeBoard(newEmergencyUpgradeBoard);
    assertEq(address(newBoard.PROTOCOL_UPGRADE_HANDLER()), PROTOCOL_UPGRADE_HANDLER);
    assertEq(newBoard.SECURITY_COUNCIL(), V31_SECURITY_COUNCIL);
    assertEq(newBoard.ZK_FOUNDATION_SAFE(), zkFoundationSafe);
  }

  function test_MainnetForkGeneratedCalls() external onlyMainnet {
    IProtocolUpgradeHandler.Call[] memory calls = script.getGeneratedCalls();
    assertEq(calls.length, 3);

    assertEq(calls[0].target, stateCheck);
    assertEq(
      calls[0].data,
      abi.encodeCall(
        ProtocolUpgradeHandlerStateCheck.checkRoles,
        (
          IProtocolUpgradeHandlerRoles(PROTOCOL_UPGRADE_HANDLER),
          V31_SECURITY_COUNCIL,
          V31_GUARDIANS,
          V31_EMERGENCY_UPGRADE_BOARD
        )
      )
    );
    assertEq(calls[1].target, PROTOCOL_UPGRADE_HANDLER);
    assertEq(calls[1].data, abi.encodeCall(ProtocolUpgradeHandler.updateGuardians, (zkFoundationSafe)));
    assertEq(calls[2].target, PROTOCOL_UPGRADE_HANDLER);
    assertEq(
      calls[2].data, abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (newEmergencyUpgradeBoard))
    );
    for (uint256 i = 0; i < calls.length; i++) {
      assertEq(calls[i].value, 0);
    }
  }

  function test_MainnetForkRevertWhen_ExecutedBeforeV31() external onlyMainnet {
    if (handler.securityCouncil() == V31_SECURITY_COUNCIL) {
      // The fork already includes v31, the ordering can't be checked.
      return;
    }
    IProtocolUpgradeHandler.UpgradeProposal memory proposal = _removeGuardiansProposal();
    _passUpgrade(proposal);

    vm.expectRevert("Unexpected Security Council");
    handler.execute(proposal);

    // Once v31 is in place the very same (still ready) proposal goes through.
    _applyV31();
    handler.execute(proposal);
    assertEq(handler.guardians(), zkFoundationSafe);
  }

  function test_MainnetForkGuardiansRoleHandedToFoundation() external onlyMainnet {
    _executeRemoveGuardians();

    assertEq(handler.guardians(), zkFoundationSafe);
    assertEq(handler.emergencyUpgradeBoard(), newEmergencyUpgradeBoard);
    // The Security Council is untouched.
    assertEq(handler.securityCouncil(), V31_SECURITY_COUNCIL);
  }

  function test_MainnetForkFoundationHoldsGuardiansRole() external onlyMainnet {
    _executeRemoveGuardians();
    bytes32 unknownId = keccak256("unknown upgrade");

    // The ZK Foundation Safe passes the guardians access control...
    vm.startPrank(zkFoundationSafe);
    vm.expectRevert("Upgrade with this id is not in the legal veto period");
    handler.extendLegalVeto(unknownId);
    vm.expectRevert("Upgrade with this id is not waiting for the approval from Guardians");
    handler.approveUpgradeGuardians(unknownId);
    vm.stopPrank();

    // ...while the Guardians multisig doesn't anymore.
    vm.startPrank(V31_GUARDIANS);
    vm.expectRevert("Only guardians is allowed to call this function");
    handler.extendLegalVeto(unknownId);
    vm.expectRevert("Only guardians is allowed to call this function");
    handler.approveUpgradeGuardians(unknownId);
    vm.stopPrank();
  }

  function test_MainnetForkOldBoardLosesEmergencyPowers() external onlyMainnet {
    _executeRemoveGuardians();

    IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
      calls: new IProtocolUpgradeHandler.Call[](0), salt: bytes32(uint256(1)), executor: V31_EMERGENCY_UPGRADE_BOARD
    });

    vm.prank(V31_EMERGENCY_UPGRADE_BOARD);
    vm.expectRevert("Only Emergency Upgrade Board is allowed to call this function");
    handler.executeEmergencyUpgrade(proposal);
  }

  function test_MainnetForkNewBoardCanExecuteEmergencyUpgrade() external onlyMainnet {
    _executeRemoveGuardians();

    IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
      calls: new IProtocolUpgradeHandler.Call[](0), salt: bytes32(uint256(2)), executor: newEmergencyUpgradeBoard
    });

    vm.prank(newEmergencyUpgradeBoard);
    handler.executeEmergencyUpgrade(proposal);

    assertEq(
      uint8(handler.upgradeState(keccak256(abi.encode(proposal)))), uint8(IProtocolUpgradeHandler.UpgradeState.Done)
    );
  }
}
