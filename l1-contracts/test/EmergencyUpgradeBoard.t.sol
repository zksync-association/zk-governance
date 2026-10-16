// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.t.sol";
import {EIP712Util} from "./utils/EIP712Util.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {MultisigMock} from "./mocks/MultisigMock.t.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

contract TestEmergencyUpgradeBoard is Test, EIP712Util {
  uint256 internal constant SECURITY_COUNCIL_MEMBERS = 12;
  uint256 internal constant SECURITY_COUNCIL_THRESHOLD = 9;
  uint256 internal constant ZK_FOUNDATION_MEMBERS = 5;
  uint256 internal constant ZK_FOUNDATION_THRESHOLD = 3;

  IProtocolUpgradeHandler protocolUpgradeHandler = IProtocolUpgradeHandler(address(new EmptyContract()));
  MultisigMock securityCouncil;
  MultisigMock zkFoundation;
  EmergencyUpgradeBoard emergencyUpgradeBoard;

  Vm.Wallet[] internal securityCouncilWallets;
  Vm.Wallet[] internal zkFoundationWallets;
  bytes32 internal emergencyUpgradeBoardDomainHash;

  /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the Security Council.
  bytes32 internal constant EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH =
    keccak256("ExecuteEmergencyUpgradeSecurityCouncil(bytes32 id)");

  /// @dev EIP-712 TypeHash for the emergency protocol upgrade execution approved by the ZK Foundation.
  bytes32 internal constant EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH =
    keccak256("ExecuteEmergencyUpgradeZKFoundation(bytes32 id)");

  constructor() {
    address[] memory securityCouncilMembers = new address[](SECURITY_COUNCIL_MEMBERS);
    Vm.Wallet[] memory securityCouncilWallets_ = new Vm.Wallet[](SECURITY_COUNCIL_MEMBERS);
    for (uint256 i = 0; i < SECURITY_COUNCIL_MEMBERS; i++) {
      securityCouncilWallets_[i] = vm.createWallet(string(abi.encodePacked("SC Account: ", i)));
    }
    securityCouncilWallets_ = Utils.sortWalletsByAddress(securityCouncilWallets_);
    for (uint256 i = 0; i < SECURITY_COUNCIL_MEMBERS; i++) {
      securityCouncilWallets.push(securityCouncilWallets_[i]);
      securityCouncilMembers[i] = securityCouncilWallets_[i].addr;
    }

    address[] memory zkFoundationMembers = new address[](ZK_FOUNDATION_MEMBERS);
    Vm.Wallet[] memory zkFoundationWallets_ = new Vm.Wallet[](ZK_FOUNDATION_MEMBERS);
    for (uint256 i = 0; i < ZK_FOUNDATION_MEMBERS; i++) {
      zkFoundationWallets_[i] = vm.createWallet(string(abi.encodePacked("Foundation Account: ", i)));
    }
    zkFoundationWallets_ = Utils.sortWalletsByAddress(zkFoundationWallets_);
    for (uint256 i = 0; i < ZK_FOUNDATION_MEMBERS; i++) {
      zkFoundationWallets.push(zkFoundationWallets_[i]);
      zkFoundationMembers[i] = zkFoundationWallets_[i].addr;
    }

    securityCouncil = new MultisigMock(securityCouncilMembers, SECURITY_COUNCIL_THRESHOLD);
    zkFoundation = new MultisigMock(zkFoundationMembers, ZK_FOUNDATION_THRESHOLD);

    emergencyUpgradeBoard =
      new EmergencyUpgradeBoard(protocolUpgradeHandler, address(securityCouncil), address(zkFoundation));
    emergencyUpgradeBoardDomainHash =
      _buildDomainHash(address(emergencyUpgradeBoard), "EmergencyUpgradeBoard", "1");
  }

  function _buildProposal(bytes32 _salt)
    internal
    view
    returns (IProtocolUpgradeHandler.UpgradeProposal memory proposal, bytes32 id)
  {
    IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](1);
    calls[0] = IProtocolUpgradeHandler.Call({target: address(0xdead), value: 0, data: hex"c0ffee"});
    proposal = IProtocolUpgradeHandler.UpgradeProposal({
      calls: calls,
      salt: _salt,
      executor: address(emergencyUpgradeBoard)
    });
    id = keccak256(abi.encode(proposal));
  }

  function _signByWallets(bytes32 _digest, Vm.Wallet[] storage _wallets, uint256 _numberOfSignatures)
    internal
    returns (bytes memory encodedSignatures)
  {
    address[] memory signers = new address[](_numberOfSignatures);
    bytes[] memory signatures = new bytes[](_numberOfSignatures);
    for (uint256 i = 0; i < _numberOfSignatures; i++) {
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(_wallets[i], _digest);
      signers[i] = _wallets[i].addr;
      signatures[i] = abi.encodePacked(r, s, v);
    }
    encodedSignatures = abi.encode(signers, signatures);
  }

  function _securityCouncilDigest(bytes32 _id) internal view returns (bytes32) {
    return _buildDigest(
      emergencyUpgradeBoardDomainHash,
      keccak256(abi.encode(EXECUTE_EMERGENCY_UPGRADE_SECURITY_COUNCIL_TYPEHASH, _id))
    );
  }

  function _zkFoundationDigest(bytes32 _id) internal view returns (bytes32) {
    return _buildDigest(
      emergencyUpgradeBoardDomainHash,
      keccak256(abi.encode(EXECUTE_EMERGENCY_UPGRADE_ZK_FOUNDATION_TYPEHASH, _id))
    );
  }

  function test_successfullyExecutesUpgradeWithTwoPartyApproval(bytes32 _salt) public {
    (IProtocolUpgradeHandler.UpgradeProposal memory proposal, bytes32 id) = _buildProposal(_salt);

    bytes memory securityCouncilSignatures =
      _signByWallets(_securityCouncilDigest(id), securityCouncilWallets, SECURITY_COUNCIL_THRESHOLD);
    bytes memory zkFoundationSignatures =
      _signByWallets(_zkFoundationDigest(id), zkFoundationWallets, ZK_FOUNDATION_THRESHOLD);

    vm.expectCall(
      address(protocolUpgradeHandler),
      abi.encodeCall(IProtocolUpgradeHandler.executeEmergencyUpgrade, (proposal))
    );
    emergencyUpgradeBoard.executeEmergencyUpgrade(
      proposal.calls, _salt, securityCouncilSignatures, zkFoundationSignatures
    );
  }

  function test_RevertWhen_NotEnoughSecurityCouncilSignatures(bytes32 _salt, uint256 _numberOfSignatures) public {
    _numberOfSignatures = bound(_numberOfSignatures, 0, SECURITY_COUNCIL_THRESHOLD - 1);
    (IProtocolUpgradeHandler.UpgradeProposal memory proposal, bytes32 id) = _buildProposal(_salt);

    bytes memory securityCouncilSignatures =
      _signByWallets(_securityCouncilDigest(id), securityCouncilWallets, _numberOfSignatures);
    bytes memory zkFoundationSignatures =
      _signByWallets(_zkFoundationDigest(id), zkFoundationWallets, ZK_FOUNDATION_THRESHOLD);

    vm.expectRevert("Invalid Security Council signatures");
    emergencyUpgradeBoard.executeEmergencyUpgrade(
      proposal.calls, _salt, securityCouncilSignatures, zkFoundationSignatures
    );
  }

  function test_RevertWhen_NotEnoughZkFoundationSignatures(bytes32 _salt, uint256 _numberOfSignatures) public {
    _numberOfSignatures = bound(_numberOfSignatures, 0, ZK_FOUNDATION_THRESHOLD - 1);
    (IProtocolUpgradeHandler.UpgradeProposal memory proposal, bytes32 id) = _buildProposal(_salt);

    bytes memory securityCouncilSignatures =
      _signByWallets(_securityCouncilDigest(id), securityCouncilWallets, SECURITY_COUNCIL_THRESHOLD);
    bytes memory zkFoundationSignatures =
      _signByWallets(_zkFoundationDigest(id), zkFoundationWallets, _numberOfSignatures);

    vm.expectRevert("Invalid ZK Foundation signatures");
    emergencyUpgradeBoard.executeEmergencyUpgrade(
      proposal.calls, _salt, securityCouncilSignatures, zkFoundationSignatures
    );
  }

  function test_RevertWhen_SignaturesForDifferentProposal(bytes32 _salt, bytes32 _differentSalt) public {
    vm.assume(_salt != _differentSalt);
    (IProtocolUpgradeHandler.UpgradeProposal memory proposal,) = _buildProposal(_salt);
    (, bytes32 differentId) = _buildProposal(_differentSalt);

    bytes memory securityCouncilSignatures =
      _signByWallets(_securityCouncilDigest(differentId), securityCouncilWallets, SECURITY_COUNCIL_THRESHOLD);
    bytes memory zkFoundationSignatures =
      _signByWallets(_zkFoundationDigest(differentId), zkFoundationWallets, ZK_FOUNDATION_THRESHOLD);

    vm.expectRevert("Invalid Security Council signatures");
    emergencyUpgradeBoard.executeEmergencyUpgrade(
      proposal.calls, _salt, securityCouncilSignatures, zkFoundationSignatures
    );
  }

  function test_ImmutableConfiguration() public {
    assertEq(address(emergencyUpgradeBoard.PROTOCOL_UPGRADE_HANDLER()), address(protocolUpgradeHandler));
    assertEq(emergencyUpgradeBoard.SECURITY_COUNCIL(), address(securityCouncil));
    assertEq(emergencyUpgradeBoard.ZK_FOUNDATION_SAFE(), address(zkFoundation));
  }
}
