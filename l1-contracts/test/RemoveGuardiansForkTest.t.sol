// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {
  ProtocolUpgradeHandlerStateCheck,
  IProtocolUpgradeHandlerRoles
} from "../src/ProtocolUpgradeHandlerStateCheck.sol";

import {SecurityCouncil} from "../src/SecurityCouncil.sol";

import {MainnetRemoveGuardians} from "../scripts/MainnetRemoveGuardians.s.sol";
import {RemoveGuardiansDeployedContracts} from "../scripts/RemoveGuardians.s.sol";
import {MainnetRedeploySecurityCouncil} from "../scripts/MainnetRedeploySecurityCouncil.s.sol";
import {SCRedeployedContracts} from "../scripts/RedeploySecurityCouncil.s.sol";

// Inside the `script-out` directory that `fs_permissions` lets scripts write to.
string constant REMOVE_GUARDIANS_OUTPUT = "./script-out/remove-guardians-fork-test.toml";

/// @dev MainnetRemoveGuardians writing its output TOML to a fixed path rather than to `DEPLOY_OUTPUT_TOML`: an
/// environment variable is process-wide, so setting it would also redirect the scripts of concurrently running tests.
contract MainnetRemoveGuardiansWithOutput is MainnetRemoveGuardians {
  function _outputPath() internal pure override returns (string memory) {
    return REMOVE_GUARDIANS_OUTPUT;
  }
}

/// @dev Verifies the guardians removal flow against a mainnet fork (`--fork-url <L1_MAINNET_RPC>`):
/// replays the v31 handler upgrade, runs the MainnetRemoveGuardians script against the result,
/// passes the generated Call[] through the regular upgrade flow of the ProtocolUpgradeHandler and
/// checks the resulting system state. Only the L2 -> L1 message proof of `startUpgrade` is skipped,
/// the upgrade is registered by writing its creation timestamp directly.
contract RemoveGuardiansForkTest is Test {
  // The governance set installed by v31, used to replay v31 and to cross-check what the script reads.
  address constant PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;
  address constant V31_PROTOCOL_UPGRADE_HANDLER_IMPL = 0x76C4c9897c610C554C948Ece32BEF1257ddE3811;
  address constant V31_SECURITY_COUNCIL = 0x29D2e773A31C07D375c50F0110422832bd044d08;
  address constant V31_GUARDIANS = 0x8f525e55F76050d8dFdDa4870DA1b3ede54E908F;
  address constant V31_EMERGENCY_UPGRADE_BOARD = 0x91989F9BB8391D3471D2672Ec001921cB14C4b7C;

  // v31 (ZIP-18) stage 0: `ProxyAdmin.upgradeAndCall(PUH proxy, newImpl, initialize(...))`, see
  // transaction-simulator decoded-calldata/2026-09-08-v31-interopB-mainnet.json.
  address constant PROTOCOL_UPGRADE_HANDLER_PROXY_ADMIN = 0x1e4c534e7ce1FF5621Ea506D99b367D7d8EFbE3e;

  // EIP-1967 implementation slot.
  bytes32 constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
  // `ProtocolUpgradeHandler.upgradeStatus` mapping slot (`forge inspect ProtocolUpgradeHandler storageLayout`).
  uint256 constant UPGRADE_STATUS_SLOT = 3;
  // Mainnet `STANDARD_LEGAL_VETO_PERIOD` and `UPGRADE_DELAY_PERIOD` of the ProtocolUpgradeHandler.
  uint256 constant LEGAL_VETO_PERIOD = 3 days;
  uint256 constant UPGRADE_DELAY_PERIOD = 9 days;
  // L1Messenger system contract on Era, the target of the ZIP action.
  address constant L1_MESSENGER = 0x0000000000000000000000000000000000008008;

  MainnetRemoveGuardians script;
  ProtocolUpgradeHandler handler;

  address zkFoundationSafe;
  address newImplementation;
  address newEmergencyUpgradeBoard;
  address stateCheck;

  // Whether the fork predates v31, and its state before the v31 replay.
  bool forkPredatesV31;
  uint256 preV31Snapshot;

  /// @dev Needs a mainnet fork (`--fork-url <L1_MAINNET_RPC>`), the tests are reported as skipped without one.
  modifier onlyMainnet() {
    vm.skip(block.chainid != 1);
    _;
  }

  function setUp() external onlyMainnet {
    handler = ProtocolUpgradeHandler(payable(PROTOCOL_UPGRADE_HANDLER));
    zkFoundationSafe = EmergencyUpgradeBoard(V31_EMERGENCY_UPGRADE_BOARD).ZK_FOUNDATION_SAFE();

    // The script reads the post-v31 state from the handler.
    forkPredatesV31 = handler.securityCouncil() != V31_SECURITY_COUNCIL;
    preV31Snapshot = vm.snapshot();
    _applyV31();

    script = new MainnetRemoveGuardians();
    script.run();

    RemoveGuardiansDeployedContracts memory deployed = script.getDeployedAddresses();
    newImplementation = deployed.protocolUpgradeHandlerImpl;
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
    _registerUpgrade(id);

    vm.warp(block.timestamp + LEGAL_VETO_PERIOD);
    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));

    vm.prank(handler.securityCouncil());
    handler.approveUpgradeSecurityCouncil(id);

    vm.warp(block.timestamp + UPGRADE_DELAY_PERIOD);
    assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Ready));
  }

  function _registerUpgrade(bytes32 _id) internal {
    bytes32 statusSlot = keccak256(abi.encode(_id, UPGRADE_STATUS_SLOT));
    // `creationTimestamp` is the lowest packed field of `UpgradeStatus`.
    vm.store(PROTOCOL_UPGRADE_HANDLER, statusSlot, bytes32(block.timestamp));
    assertEq(uint8(handler.upgradeState(_id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));
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
    assertEq(calls.length, 4);

    assertEq(calls[0].target, stateCheck);
    assertEq(
      calls[0].data,
      abi.encodeCall(
        ProtocolUpgradeHandlerStateCheck.checkRoles,
        (IProtocolUpgradeHandlerRoles(PROTOCOL_UPGRADE_HANDLER), V31_SECURITY_COUNCIL, V31_EMERGENCY_UPGRADE_BOARD)
      )
    );
    assertEq(calls[1].target, PROTOCOL_UPGRADE_HANDLER_PROXY_ADMIN);
    assertEq(
      calls[1].data,
      abi.encodeCall(
        ProxyAdmin.upgradeAndCall,
        (ITransparentUpgradeableProxy(PROTOCOL_UPGRADE_HANDLER), newImplementation, bytes(""))
      )
    );
    assertEq(calls[2].target, PROTOCOL_UPGRADE_HANDLER);
    assertEq(calls[2].data, abi.encodeCall(ProtocolUpgradeHandler.updateZkFoundation, (zkFoundationSafe)));
    assertEq(calls[3].target, PROTOCOL_UPGRADE_HANDLER);
    assertEq(
      calls[3].data, abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (newEmergencyUpgradeBoard))
    );
    for (uint256 i = 0; i < calls.length; i++) {
      assertEq(calls[i].value, 0);
    }
  }

  /// @dev Goes back to the fork state before the v31 replay, keeping the contracts the script deployed.
  function _revertV31() internal {
    address[3] memory deployed = [newImplementation, newEmergencyUpgradeBoard, stateCheck];
    bytes[3] memory code = [deployed[0].code, deployed[1].code, deployed[2].code];
    vm.revertTo(preV31Snapshot);
    for (uint256 i = 0; i < deployed.length; i++) {
      vm.etch(deployed[i], code[i]);
    }
  }

  function test_MainnetForkRevertWhen_ScriptRunsBeforeV31() external onlyMainnet {
    // Needs a fork that predates v31.
    vm.skip(!forkPredatesV31);
    vm.revertTo(preV31Snapshot);

    MainnetRemoveGuardians preV31Script = new MainnetRemoveGuardians();
    vm.expectRevert("The handler must run the v31 implementation");
    preV31Script.run();
  }

  function test_MainnetForkRevertWhen_ScriptRunsAfterRemoval() external onlyMainnet {
    _executeRemoveGuardians();

    MainnetRemoveGuardians postRemovalScript = new MainnetRemoveGuardians();
    vm.expectRevert("Guardians are already removed");
    postRemovalScript.run();
  }

  function test_MainnetForkRevertWhen_ExecutedBeforeV31() external onlyMainnet {
    // Needs a fork that predates v31, the ordering can't be checked once the fork includes it.
    vm.skip(!forkPredatesV31);
    IProtocolUpgradeHandler.UpgradeProposal memory proposal = _removeGuardiansProposal();
    _revertV31();
    _passUpgrade(proposal);

    vm.expectRevert("Unexpected Security Council");
    handler.execute(proposal);

    // Once v31 is in place the very same (still ready) proposal goes through.
    _applyV31();
    handler.execute(proposal);
    assertEq(handler.zkFoundation(), zkFoundationSafe);
  }

  function test_MainnetForkHandlerUpgraded() external onlyMainnet {
    ProtocolUpgradeHandler v31Implementation = ProtocolUpgradeHandler(payable(V31_PROTOCOL_UPGRADE_HANDLER_IMPL));
    _executeRemoveGuardians();

    assertEq(address(uint160(uint256(vm.load(PROTOCOL_UPGRADE_HANDLER, IMPLEMENTATION_SLOT)))), newImplementation);

    // Roles
    assertEq(handler.zkFoundation(), zkFoundationSafe);
    assertEq(handler.emergencyUpgradeBoard(), newEmergencyUpgradeBoard);
    assertEq(handler.securityCouncil(), V31_SECURITY_COUNCIL);

    // The immutables are copied from the v31 implementation.
    assertEq(handler.L2_PROTOCOL_GOVERNOR(), v31Implementation.L2_PROTOCOL_GOVERNOR());
    assertEq(address(handler.ERA_CHAIN_TYPE_MANAGER()), address(v31Implementation.ERA_CHAIN_TYPE_MANAGER()));
    assertEq(address(handler.ZKSYNC_OS_CHAIN_TYPE_MANAGER()), address(v31Implementation.ZKSYNC_OS_CHAIN_TYPE_MANAGER()));
    assertEq(address(handler.BRIDGE_HUB()), address(v31Implementation.BRIDGE_HUB()));
    assertEq(address(handler.L1_NULLIFIER()), address(v31Implementation.L1_NULLIFIER()));
    assertEq(address(handler.L1_ASSET_ROUTER()), address(v31Implementation.L1_ASSET_ROUTER()));
    assertEq(address(handler.L1_NATIVE_TOKEN_VAULT()), address(v31Implementation.L1_NATIVE_TOKEN_VAULT()));
    assertEq(address(handler.CHAIN_ASSET_HANDLER()), address(v31Implementation.CHAIN_ASSET_HANDLER()));
    assertEq(handler.ERA_CHAIN_ID(), v31Implementation.ERA_CHAIN_ID());
  }

  function test_MainnetForkRevertWhen_ReinitializedAfterUpgrade() external onlyMainnet {
    _executeRemoveGuardians();

    vm.expectRevert(Initializable.InvalidInitialization.selector);
    handler.initialize(address(1), address(2), address(3));
  }

  function test_MainnetForkInFlightUpgradeSurvives() external onlyMainnet {
    _applyV31();
    IProtocolUpgradeHandler.UpgradeProposal memory inFlight = IProtocolUpgradeHandler.UpgradeProposal({
      calls: new IProtocolUpgradeHandler.Call[](0), salt: keccak256("in flight"), executor: address(0)
    });
    bytes32 inFlightId = keccak256(abi.encode(inFlight));
    _registerUpgrade(inFlightId);

    _executeRemoveGuardians();

    // The in-flight upgrade kept its creation timestamp: it is still waiting for an approval and the ZK Foundation
    // (the new holder of the role) can approve it.
    assertEq(uint8(handler.upgradeState(inFlightId)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));
    vm.prank(zkFoundationSafe);
    handler.approveUpgradeZkFoundation(inFlightId);
    (,, bool zkFoundationApproval,,) = handler.upgradeStatus(inFlightId);
    assertTrue(zkFoundationApproval);
  }

  function test_MainnetForkFoundationHoldsRole() external onlyMainnet {
    _executeRemoveGuardians();
    bytes32 unknownId = keccak256("unknown upgrade");

    // The ZK Foundation Safe passes the access control...
    vm.startPrank(zkFoundationSafe);
    vm.expectRevert("Upgrade with this id is not in the legal veto period");
    handler.extendLegalVeto(unknownId);
    vm.expectRevert("Upgrade with this id is not waiting for the approval from ZK Foundation");
    handler.approveUpgradeZkFoundation(unknownId);
    vm.stopPrank();

    // ...while the Guardians multisig doesn't anymore.
    vm.startPrank(V31_GUARDIANS);
    vm.expectRevert("Only ZK Foundation is allowed to call this function");
    handler.extendLegalVeto(unknownId);
    vm.expectRevert("Only ZK Foundation is allowed to call this function");
    handler.approveUpgradeZkFoundation(unknownId);
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

  function test_MainnetForkScriptOutput() external onlyMainnet {
    vm.createDir("./script-out", true);
    new MainnetRemoveGuardiansWithOutput().run();
    string memory toml = vm.readFile(REMOVE_GUARDIANS_OUTPUT);
    vm.removeFile(REMOVE_GUARDIANS_OUTPUT);

    IProtocolUpgradeHandler.UpgradeProposal memory proposal = _removeGuardiansProposal();
    assertEq(vm.parseTomlAddress(toml, ".new_puh_impl"), newImplementation);
    assertEq(vm.parseTomlAddress(toml, ".new_emergency_upgrade_board"), newEmergencyUpgradeBoard);
    assertEq(vm.parseTomlAddress(toml, ".state_check"), stateCheck);
    assertEq(vm.parseTomlBytes(toml, ".governance_calls"), abi.encode(proposal.calls));
    assertEq(vm.parseTomlAddress(toml, ".zip_target"), L1_MESSENGER);
    assertEq(vm.parseTomlBytes(toml, ".zip_calldata"), abi.encodeWithSignature("sendToL1(bytes)", abi.encode(proposal)));
    assertEq(vm.parseTomlBytes32(toml, ".upgrade_id"), keccak256(abi.encode(proposal)));
  }

  function _redeploySecurityCouncil() internal returns (MainnetRedeploySecurityCouncil _redeploy) {
    vm.setEnv("PRIVATE_KEY", vm.toString(vm.createWallet("security council deployer").privateKey));
    _redeploy = new MainnetRedeploySecurityCouncil();
    _redeploy.run();
  }

  function test_MainnetForkRevertWhen_SecurityCouncilRedeployedBeforeRemoval() external onlyMainnet {
    MainnetRedeploySecurityCouncil redeploy = new MainnetRedeploySecurityCouncil();
    vm.expectRevert("The Guardians must be removed from the handler first");
    redeploy.run();
  }

  function test_MainnetForkRevertWhen_SecurityCouncilRedeployedWithAnotherZkFoundation() external onlyMainnet {
    _executeRemoveGuardians();
    vm.prank(PROTOCOL_UPGRADE_HANDLER);
    handler.updateZkFoundation(makeAddr("another ZK Foundation"));

    MainnetRedeploySecurityCouncil redeploy = new MainnetRedeploySecurityCouncil();
    vm.expectRevert("Handler and board disagree on the ZK Foundation");
    redeploy.run();
  }

  function test_MainnetForkSecurityCouncilRedeployedAfterRemoval() external onlyMainnet {
    _executeRemoveGuardians();
    MainnetRedeploySecurityCouncil redeploy = _redeploySecurityCouncil();
    SCRedeployedContracts memory redeployed = redeploy.getDeployedAddresses();

    // The retained members are exactly the members of the current (v31) Security Council.
    SecurityCouncil newSecurityCouncil = SecurityCouncil(redeployed.securityCouncil);
    assertEq(address(newSecurityCouncil.PROTOCOL_UPGRADE_HANDLER()), PROTOCOL_UPGRADE_HANDLER);
    for (uint256 i = 0; i < 8; i++) {
      assertEq(newSecurityCouncil.members(i), SecurityCouncil(V31_SECURITY_COUNCIL).members(i));
    }
    EmergencyUpgradeBoard newBoard = EmergencyUpgradeBoard(redeployed.emergencyUpgradeBoard);
    assertEq(address(newBoard.PROTOCOL_UPGRADE_HANDLER()), PROTOCOL_UPGRADE_HANDLER);
    assertEq(newBoard.SECURITY_COUNCIL(), redeployed.securityCouncil);
    assertEq(newBoard.ZK_FOUNDATION_SAFE(), zkFoundationSafe);

    // The generated calls rotate both through the regular upgrade flow.
    IProtocolUpgradeHandler.UpgradeProposal memory rotation = IProtocolUpgradeHandler.UpgradeProposal({
      calls: redeploy.getGeneratedCalls(), salt: bytes32(0), executor: address(0)
    });
    _passUpgrade(rotation);
    handler.execute(rotation);
    assertEq(handler.securityCouncil(), redeployed.securityCouncil);
    assertEq(handler.emergencyUpgradeBoard(), redeployed.emergencyUpgradeBoard);
    assertEq(handler.zkFoundation(), zkFoundationSafe);
  }
}
