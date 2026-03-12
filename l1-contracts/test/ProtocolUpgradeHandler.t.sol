// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";

import {Callee} from "./utils/Callee.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {StateTransitionManagerMock} from "./mocks/StateTransitionManagerMock.t.sol";
import {BridgehubMock} from "./mocks/BridgehubMock.t.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {IStateTransitionManager} from "../src/interfaces/IStateTransitionManager.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {MockChainAssetHandler} from "./mocks/MockChainAssetHandler.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";

struct ZkSyncProofData {
    uint256 _l2BatchNumber;
    uint256 _l2MessageIndex;
    uint16 _l2TxNumberInBatch;
    bytes32[] _proof;
}

contract TestProtocolUpgradeHandler is Test {
    using stdStorage for StdStorage;

    address securityCouncil;
    address guardians;
    address emergencyUpgradeBoard;
    address l2ProtocolGovernor;
    IChainTypeManager chainTypeManager;
    IBridgeHub bridgeHub;
    IPausable l1Nullifier;
    IPausable l1AssetRouter;
    IPausable l1NativeTokenVault;

    ProtocolUpgradeHandler handler;
    MockChainAssetHandler chainAssetHandler;
    uint256[] chainIds;

    function _createProofData(IProtocolUpgradeHandler.UpgradeProposal memory _proposal, bool _isCorrect)
        internal
        returns (ZkSyncProofData memory)
    {
        uint256 batchNumber = 100;
        uint256 index = 0;
        uint16 txNumberInBatch = _isCorrect ? 10 : 11;
        bytes32[] memory proof = new bytes32[](11);
        bytes memory upgradeMessage = abi.encode(_proposal);

        IBridgeHub.L2Message memory l2ToL1Message =
            IBridgeHub.L2Message({txNumberInBatch: txNumberInBatch, sender: l2ProtocolGovernor, data: upgradeMessage});

        vm.mockCall(
            address(bridgeHub),
            abi.encodeWithSelector(
                IBridgeHub.proveL2MessageInclusion.selector, chainIds[1], batchNumber, index, l2ToL1Message, proof
            ),
            abi.encode(_isCorrect)
        );

        return ZkSyncProofData(batchNumber, index, txNumberInBatch, proof);
    }

    function _resetUpgradeCycle() internal {
        stdstore.target(address(handler)).sig("protocolFrozenUntil()").checked_write(uint256(0));
        stdstore.target(address(handler)).sig("lastFreezeStatusInUpgradeCycle()").checked_write(uint256(0));
    }

    function _expectFreezeAttempt() internal {
        for (uint256 i = 0; i < chainIds.length; i++) {
            vm.expectCall(
                address(chainTypeManager),
                abi.encodeWithSelector(IChainTypeManager.freezeChain.selector, (chainIds[i]))
            );
        }
        vm.expectCall(address(bridgeHub), abi.encodeWithSelector(IPausable.pause.selector));
        vm.expectCall(address(l1AssetRouter), abi.encodeWithSelector(IPausable.pause.selector));
    }

    function _emptyProposal(bytes32 _salt) internal returns (IProtocolUpgradeHandler.UpgradeProposal memory) {
        return IProtocolUpgradeHandler.UpgradeProposal({
            calls: new IProtocolUpgradeHandler.Call[](0),
            executor: address(0),
            salt: _salt
        });
    }

    function _startUpgrade(IProtocolUpgradeHandler.UpgradeProposal memory proposal) internal returns (bytes32 id) {
        id = keccak256(abi.encode(proposal));
        ZkSyncProofData memory correctProofData = _createProofData(proposal, true);
        handler.startUpgrade(
            correctProofData._l2BatchNumber,
            correctProofData._l2MessageIndex,
            correctProofData._l2TxNumberInBatch,
            correctProofData._proof,
            proposal
        );
    }

    function _approveBySecurityCouncil(bytes32 _id) internal {
        vm.prank(securityCouncil);
        handler.approveUpgradeSecurityCouncil(_id);
    }

    function _approveByGuardians(bytes32 _id) internal {
        vm.prank(guardians);
        handler.approveUpgradeGuardians(_id);
    }

    function _passLegalVeto(bool _extendedLegalPeriod, bytes32 _id) internal {
        if (_extendedLegalPeriod) {
            (uint48 creationTimestamp,,,,) = handler.upgradeStatus(_id);
            vm.warp(creationTimestamp + 3 days - 1);
            vm.prank(guardians);
            handler.extendLegalVeto(_id);
            vm.warp(creationTimestamp + 7 days);
        } else {
            (uint48 creationTimestamp,,,,) = handler.upgradeStatus(_id);
            vm.warp(creationTimestamp + 3 days);
        }
    }

    function _makeUpgradeReady(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil,
        bytes32 _id,
        uint256 _delayAfterApprove
    ) internal {
        _passLegalVeto(_extendedLegalPeriod, _id);
        vm.assume(_approvedByGuardians || _approvedBySecurityCouncil);
        if (_approvedByGuardians) {
            _approveByGuardians(_id);
        }

        if (_approvedBySecurityCouncil) {
            _approveBySecurityCouncil(_id);
        } else {
            vm.warp(block.timestamp + 30 days);
        }
        uint256 delayAfterApprove = bound(_delayAfterApprove, 1, type(uint256).max - block.timestamp - 5 days);
        vm.warp(block.timestamp + 5 days + delayAfterApprove);
    }

    constructor() {
        chainIds.push(1);
        chainIds.push(300);
        chainIds.push(324);
        securityCouncil = makeAddr("securityCouncil");
        guardians = makeAddr("guardians");
        emergencyUpgradeBoard = makeAddr("emergencyUpgradeBoard");
        l2ProtocolGovernor = makeAddr("l2ProtocolGovernor");
        chainTypeManager = IChainTypeManager(address(new StateTransitionManagerMock(chainIds)));
        BridgehubMock bridgehubMock = new BridgehubMock(chainIds);
        for (uint256 i = 0; i < chainIds.length; i++) {
            bridgehubMock.setChainTypeManager(chainIds[i], address(chainTypeManager));
        }
        bridgeHub = IBridgeHub(address(bridgehubMock));
        l1Nullifier = IPausable(address(new EmptyContract()));
        l1AssetRouter = IPausable(address(new EmptyContract()));
        l1NativeTokenVault = IPausable(address(new EmptyContract()));
        chainAssetHandler = new MockChainAssetHandler();

        handler = _deployProtocolUpgradeHanlder(
            securityCouncil,
            guardians,
            emergencyUpgradeBoard,
            l2ProtocolGovernor,
            chainTypeManager,
            bridgeHub,
            l1Nullifier,
            l1AssetRouter,
            l1NativeTokenVault,
            chainIds[1]
        );
    }

    function _deployProtocolUpgradeHanlder(
        address securityCouncil,
        address guardians,
        address emergencyUpgradeBoard,
        address l2ProtocolGovernor,
        IChainTypeManager chainTypeManager,
        IBridgeHub bridgeHub,
        IPausable l1Nullifier,
        IPausable l1AssetRouter,
        IPausable l1NativeTokenVault,
        uint256 eraChainId
    ) internal returns (ProtocolUpgradeHandler handler) {
        ProtocolUpgradeHandler impl = new ProtocolUpgradeHandler(
            l2ProtocolGovernor,
            bridgeHub,
            l1Nullifier,
            l1AssetRouter,
            l1NativeTokenVault,
            chainAssetHandler,
            eraChainId
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            makeAddr("handlerOwner"),
            abi.encodeCall(ProtocolUpgradeHandler.initialize, (securityCouncil, guardians, emergencyUpgradeBoard))
        );

        handler = ProtocolUpgradeHandler(payable(proxy));
    }

    function test_constructorEvents() public {
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeSecurityCouncil(address(0), securityCouncil);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeGuardians(address(0), guardians);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeEmergencyUpgradeBoard(address(0), emergencyUpgradeBoard);

        ProtocolUpgradeHandler testHandler = _deployProtocolUpgradeHanlder(
            securityCouncil,
            guardians,
            emergencyUpgradeBoard,
            l2ProtocolGovernor,
            chainTypeManager,
            bridgeHub,
            l1Nullifier,
            l1AssetRouter,
            l1NativeTokenVault,
            chainIds[1]
        );
        assertEq(testHandler.securityCouncil(), securityCouncil);
        assertEq(testHandler.guardians(), guardians);
        assertEq(testHandler.emergencyUpgradeBoard(), emergencyUpgradeBoard);
        assertEq(testHandler.L2_PROTOCOL_GOVERNOR(), l2ProtocolGovernor);
        assertEq(address(testHandler.BRIDGE_HUB()), address(bridgeHub));
        assertEq(address(testHandler.L1_NULLIFIER()), address(l1Nullifier));
        assertEq(address(testHandler.L1_ASSET_ROUTER()), address(l1AssetRouter));
        assertEq(address(testHandler.L1_NATIVE_TOKEN_VAULT()), address(l1NativeTokenVault));
        assertEq(testHandler.ERA_CHAIN_ID(), chainIds[1]);
    }

    function test_StateUpgradeIncorrectProof() public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal(bytes32("1"));
        ZkSyncProofData memory incorrectProofData = _createProofData(proposal, false);
        vm.expectRevert("Failed to check upgrade proposal initiation");
        handler.startUpgrade(
            incorrectProofData._l2BatchNumber,
            incorrectProofData._l2MessageIndex,
            incorrectProofData._l2TxNumberInBatch,
            incorrectProofData._proof,
            proposal
        );
    }

    function test_StartUpgradeCantReuseProposal() public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal(bytes32("2"));
        ZkSyncProofData memory correctProofData = _createProofData(proposal, true);

        handler.startUpgrade(
            correctProofData._l2BatchNumber,
            correctProofData._l2MessageIndex,
            correctProofData._l2TxNumberInBatch,
            correctProofData._proof,
            proposal
        );

        vm.expectRevert("Upgrade with this id already exists");
        handler.startUpgrade(
            correctProofData._l2BatchNumber,
            correctProofData._l2MessageIndex,
            correctProofData._l2TxNumberInBatch,
            correctProofData._proof,
            proposal
        );
    }

    function test_StartUpgrade() public {
        // It is assumed that ZKsync Era has completely correctly implemented message proving, i.e. we will consider
        // two cases:
        // - proof is correct
        // - proof is not correct
        //
        // But we will not go deeper into the content of the structure of the proof itself.

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal(bytes32("3"));
        bytes32 id = keccak256(abi.encode(proposal));
        IProtocolUpgradeHandler.UpgradeStatus memory expectedStatus = IProtocolUpgradeHandler.UpgradeStatus({
            creationTimestamp: uint48(block.timestamp),
            securityCouncilApprovalTimestamp: 0,
            guardiansApproval: false,
            guardiansExtendedLegalVeto: false,
            executed: false
        });

        ZkSyncProofData memory correctProofData = _createProofData(proposal, true);

        // Now, let's successfully start the upgrade
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.UpgradeStarted(id, proposal);
        handler.startUpgrade(
            correctProofData._l2BatchNumber,
            correctProofData._l2MessageIndex,
            correctProofData._l2TxNumberInBatch,
            correctProofData._proof,
            proposal
        );

        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));
    }

    function test_RevertWhen_ApproveSecurityCouncilInLegalVeto() public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal(bytes32("4"));
        bytes32 id = keccak256(abi.encode(proposal));
        vm.expectRevert("Upgrade with this id is not waiting for the approval from Security Council");
        vm.prank(securityCouncil);
        handler.approveUpgradeSecurityCouncil(id);
    }

    function test_RevertWhen_ApproveGuardiansInLegalVeto() public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal(bytes32("5"));
        bytes32 id = keccak256(abi.encode(proposal));
        vm.expectRevert("Upgrade with this id is not waiting for the approval from Guardians");
        vm.prank(guardians);
        handler.approveUpgradeGuardians(id);
    }

    function test_RevertWhen_ApproveUpgradeSecurityCouncilOnlySecurityCouncil() public {
        vm.expectRevert("Only Security Council is allowed to call this function");
        handler.approveUpgradeSecurityCouncil(bytes32(uint256(0x01)));
    }

    function test_RevertWhen_SoftFreezeOnlySecurityCouncil() public {
        vm.expectRevert("Only Security Council is allowed to call this function");
        handler.softFreeze(new uint256[](0), true, true);
    }

    function test_RevertWhen_HardFreezeOnlySecurityCouncil() public {
        vm.expectRevert("Only Security Council is allowed to call this function");
        handler.hardFreeze(new uint256[](0), true, true);
    }

    function test_RevertWhen_ExtendLegalVetoOnlyGuardians() public {
        vm.expectRevert("Only guardians is allowed to call this function");
        handler.extendLegalVeto(bytes32(uint256(0x01)));
    }

    function test_RevertWhen_ApproveUpgradeGuardiansOnlyGuardians() public {
        vm.expectRevert("Only guardians is allowed to call this function");
        handler.approveUpgradeGuardians(bytes32(uint256(0x01)));
    }

    function test_RevertWhen_ApproveUpgradeSecurityCouncilNotStarted() public {
        vm.prank(securityCouncil);
        vm.expectRevert("Upgrade with this id is not waiting for the approval from Security Council");
        handler.approveUpgradeSecurityCouncil(bytes32(uint256(0x01)));
    }

    function test_LegalVetoNotEndAfterThreeDaysMinusOneSecond() public {
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("6")));
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));

        vm.warp(block.timestamp + 3 days - 1);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));
    }

    function test_ExtendedLegalVetoNotEndAfterSevenDaysMinusOneSecond() public {
        uint256 startTimestamp = block.timestamp;
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("8")));
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));

        vm.warp(startTimestamp + 3 days - 1);
        vm.prank(guardians);
        handler.extendLegalVeto(id);
        vm.warp(startTimestamp + 7 days - 1);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));
    }

    function test_CheckStatusAfterLegalVetoEnd(bool _extendedLegalPeriod) public {
        uint256 startTimestamp = block.timestamp;
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("9")));
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.LegalVetoPeriod));

        _passLegalVeto(_extendedLegalPeriod, id);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));
    }

    function test_ApproveUpgradeSecurityCouncilAfterPassingLegalVeto(bool _extendedLegalPeriod) public {
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("10")));

        _passLegalVeto(_extendedLegalPeriod, id);
        vm.prank(securityCouncil);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.UpgradeApprovedBySecurityCouncil(id);
        handler.approveUpgradeSecurityCouncil(id);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.ExecutionPending));
    }

    function testApproveUpgradeSecurityCouncilAfterLegalVetoReadyStatusAfterOneDay(bool _extendedLegalPeriod) public {
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("12")));

        _passLegalVeto(_extendedLegalPeriod, id);
        vm.prank(securityCouncil);
        handler.approveUpgradeSecurityCouncil(id);
        vm.warp(block.timestamp + 5 days);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Ready));
    }

    function testApproveUpgradeSecurityCouncilAfterLegalVetoExecutionPendingStatusAfterOneDayMinusOne(
        bool _extendedLegalPeriod
    ) public {
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("14")));

        _passLegalVeto(_extendedLegalPeriod, id);
        vm.prank(securityCouncil);
        handler.approveUpgradeSecurityCouncil(id);
        vm.warp(block.timestamp + 1 days - 1);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.ExecutionPending));
    }

    function testApproveUpgradeGuardiansNotWaiting(bool _extendedOrNotLegalVeto) public {
        bytes32 id = _startUpgrade(_emptyProposal(bytes32("16")));
        _passLegalVeto(_extendedOrNotLegalVeto, id);
        _approveBySecurityCouncil(id);

        vm.prank(guardians);
        vm.expectRevert("Upgrade with this id is not waiting for the approval from Guardians");
        handler.approveUpgradeGuardians(bytes32(uint256(0x01)));
    }

    function testApprovalFromGuardians(bool _extendedOrNotLegalVeto) public {
        bytes32 id = _startUpgrade(_emptyProposal("20"));
        _passLegalVeto(_extendedOrNotLegalVeto, id);

        IProtocolUpgradeHandler.UpgradeStatus memory expectedStatus = IProtocolUpgradeHandler.UpgradeStatus({
            creationTimestamp: uint48(block.timestamp),
            securityCouncilApprovalTimestamp: 0,
            guardiansApproval: true,
            guardiansExtendedLegalVeto: false,
            executed: false
        });

        vm.prank(guardians);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.UpgradeApprovedByGuardians(id);
        handler.approveUpgradeGuardians(id);
    }

    function testUpgradeExpiration(bool _extendedOrNotLegalVeto) public {
        bytes32 id = _startUpgrade(_emptyProposal("20"));
        _passLegalVeto(_extendedOrNotLegalVeto, id);

        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));

        vm.warp(block.timestamp + 30 days);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Expired));
    }

    function testUpgradeReadyUnderGuardiansApproval(bool _extendedOrNotLegalVeto) public {
        bytes32 id = _startUpgrade(_emptyProposal("21"));
        _passLegalVeto(_extendedOrNotLegalVeto, id);

        _approveByGuardians(id);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Waiting));

        vm.warp(block.timestamp + 30 days);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.ExecutionPending));

        vm.warp(block.timestamp + 5 days);
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Ready));
    }

    function testExecuteUpgradeOnlyReady(bool _extendedOrNotLegalVeto) public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("22");
        bytes32 id = _startUpgrade(proposal);
        _passLegalVeto(_extendedOrNotLegalVeto, id);

        _approveByGuardians(id);

        vm.expectRevert("Upgrade is not yet ready");
        handler.execute(proposal);

        _approveBySecurityCouncil(id);
        vm.expectRevert("Upgrade is not yet ready");
        handler.execute(proposal);

        // Now, it should work fine.

        vm.warp(block.timestamp + 5 days);

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.UpgradeExecuted(id);
        handler.execute(proposal);
    }

    function testExecuteMsgSenderAuthorized(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil,
        uint256 _delayAfterApprove
    ) public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("23");
        proposal.executor = makeAddr("executor");
        bytes32 id = _startUpgrade(proposal);
        _makeUpgradeReady(
            _extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id, _delayAfterApprove
        );

        vm.expectRevert("msg.sender is not authorized to perform the upgrade");
        handler.execute(proposal);

        vm.prank(proposal.executor);
        handler.execute(proposal);
    }

    function testExecuteReentrancy(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil,
        uint256 _delayAfterApprove
    ) public {
        Callee callee = new Callee();
        IProtocolUpgradeHandler.Call memory call = IProtocolUpgradeHandler.Call({
            target: address(callee),
            value: 0,
            data: abi.encodeWithSelector(Callee.reenterCaller.selector)
        });
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](1);
        calls[0] = call;
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            // Anyone can execute
            executor: address(0x0),
            salt: bytes32(0)
        });
        callee.setCalldataForReentrancy(abi.encodeWithSelector(IProtocolUpgradeHandler.execute.selector, proposal));

        bytes32 id = _startUpgrade(proposal);
        _makeUpgradeReady(
            _extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id, _delayAfterApprove
        );
        vm.expectRevert("Upgrade is not yet ready");
        handler.execute(proposal);
    }

    function testExecuteCorrectData(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil,
        uint256 _delayAfterApprove
    ) public {
        Callee callee = new Callee();

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 100;
        values[2] = 150;

        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = hex"";
        calldatas[1] = hex"abacaba1";
        calldatas[2] = hex"bababab1";

        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](3);

        for (uint256 i = 0; i < 3; i++) {
            calls[i] = IProtocolUpgradeHandler.Call({target: address(callee), value: values[i], data: calldatas[i]});
        }

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            // Anyone can execute
            executor: address(0x0),
            salt: bytes32(0)
        });
        bytes32 id = _startUpgrade(proposal);
        _makeUpgradeReady(
            _extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id, _delayAfterApprove
        );

        vm.deal(address(handler), 1 ether);
        handler.execute(proposal);

        uint256[] memory recordedValues = callee.getRecordedValues();
        bytes[] memory recordedCalldatas = callee.getRecordedCalldatas();

        assertEq(recordedValues, values);
        // Foundry does not allowed comparing bytes[] out of the box, so we do this instead
        assertEq(keccak256(abi.encode(calldatas)), keccak256(abi.encode(recordedCalldatas)));
    }

    function testRevertWhen_UpdateSecurityCouncilOnlySelf() public {
        vm.expectRevert("Only upgrade handler contract itself is allowed to call this function");
        handler.updateSecurityCouncil(securityCouncil);
    }

    function test_RevertWhen_UpdateGuardiansOnlySelf() public {
        vm.expectRevert("Only upgrade handler contract itself is allowed to call this function");
        handler.updateSecurityCouncil(securityCouncil);
    }

    function test_RevertWhen_UpdateEmergencyProtocolBoardOnlySelf() public {
        vm.expectRevert("Only upgrade handler contract itself is allowed to call this function");
        handler.updateEmergencyUpgradeBoard(emergencyUpgradeBoard);
    }

    function testUpdateGuadiansAndSecurityCouncil(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil,
        uint256 _delayAfterApprove
    ) public {
        address newSecurityCouncil = address(0x1000);
        address newGuardians = address(0x1001);

        // Just in case so that the test makes sense
        assertNotEq(newSecurityCouncil, securityCouncil);
        assertNotEq(newGuardians, guardians);

        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](2);
        calls[0] = IProtocolUpgradeHandler.Call({
            target: address(handler),
            value: 0,
            data: abi.encodeWithSelector(ProtocolUpgradeHandler.updateSecurityCouncil.selector, newSecurityCouncil)
        });
        calls[1] = IProtocolUpgradeHandler.Call({
            target: address(handler),
            value: 0,
            data: abi.encodeWithSelector(ProtocolUpgradeHandler.updateGuardians.selector, newGuardians)
        });

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            // Anyone can execute
            executor: address(0x0),
            salt: bytes32(0)
        });

        bytes32 id = _startUpgrade(proposal);
        _makeUpgradeReady(
            _extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id, _delayAfterApprove
        );
        handler.execute(proposal);

        assertEq(handler.securityCouncil(), newSecurityCouncil);
        assertEq(handler.guardians(), newGuardians);
    }

    function test_softFreeze() public {
        _resetUpgradeCycle();
        uint256 protocolFrozenUntil = block.timestamp + 12 hours;
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.SoftFreeze(protocolFrozenUntil, new uint256[](0), true);
        _expectFreezeAttempt();

        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        assertEq(uint256(handler.lastFreezeStatusInUpgradeCycle()), uint256(IProtocolUpgradeHandler.FreezeStatus.Soft));
        assertEq(protocolFrozenUntil, handler.protocolFrozenUntil());
    }

    function test_RevertWhen_ReinforceFreezeWithoutFreeze() public {
        _resetUpgradeCycle();
        vm.expectRevert("Protocol should be already frozen");
        handler.reinforceFreeze(new uint256[](0), true, true);
    }

    function test_RevertWhen_ReinforceFreezeOneChainWithoutFreeze(uint256 _chainId) public {
        _resetUpgradeCycle();
        vm.expectRevert("Protocol should be already frozen");
        handler.reinforceFreezeOneChain(_chainId);
    }

    function test_softFreezeReinforceFreeze(uint256 _timeAfterFreeze) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256 timeAfterFreeze = bound(_timeAfterFreeze, block.timestamp, block.timestamp + 12 hours);
        vm.warp(timeAfterFreeze);
        _expectFreezeAttempt();
        handler.reinforceFreeze(new uint256[](0), true, true);
    }

    function test_softFreezeReinforceFreezeOneChain(uint256 _timeAfterFreeze, uint8 _chainIdPos) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256 timeAfterFreeze = bound(_timeAfterFreeze, block.timestamp, block.timestamp + 12 hours);
        vm.warp(timeAfterFreeze);
        uint256 chainIdPos = bound(_chainIdPos, 0, chainIds.length - 1);
        uint256 chainId = chainIds[chainIdPos];
        handler.reinforceFreezeOneChain(chainId);
    }

    function test_RevertWhen_softFreezeReinforceFreezeOneChainChainIdIsNotRegistered(
        uint256 _timeAfterFreeze,
        uint256 _chainId
    ) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256 timeAfterFreeze = bound(_timeAfterFreeze, block.timestamp, block.timestamp + 12 hours);
        for (uint256 i = 0; i < chainIds.length; i++) {
            vm.assume(chainIds[i] != _chainId);
        }
        vm.warp(timeAfterFreeze);
        vm.expectRevert();
        handler.reinforceFreezeOneChain(_chainId);
    }

    function test_unfreezeAfterSoftFreezeSecurityCouncil(uint256 _ufreezeAfter) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);
        _ufreezeAfter = bound(_ufreezeAfter, block.timestamp, type(uint256).max);
        vm.warp(_ufreezeAfter);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);
        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterSoftFreeze)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_unfreezeAfterHardFreezeSecurityCouncil(uint256 _ufreezeAfter) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);
        _ufreezeAfter = bound(_ufreezeAfter, block.timestamp, type(uint256).max);
        vm.warp(_ufreezeAfter);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);
        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterHardFreeze)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_RevertWhen_hardFreezeAfterHardFreezeSecurityCouncil(uint256 _hardFreezeAfter) public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);
        _hardFreezeAfter = bound(_hardFreezeAfter, block.timestamp, type(uint256).max);
        vm.warp(_hardFreezeAfter);
        vm.expectRevert("Protocol can't be hard frozen");
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);
    }

    function test_Receive() public {
        address randomAddress = address(0x1000);
        vm.deal(address(randomAddress), 1 ether);
        vm.prank(randomAddress);
        payable(handler).send(1 ether);
    }

    function test_revertWhen_ExecuteSameEmergencyProposalMultipleTimes() public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("22");
        proposal.executor = emergencyUpgradeBoard;
        bytes32 id = keccak256(abi.encode(proposal));
        vm.startPrank(proposal.executor);
        // once
        handler.executeEmergencyUpgrade(proposal, new uint256[](0), true, true);
        // state is done
        assertEq(uint8(handler.upgradeState(id)), uint8(IProtocolUpgradeHandler.UpgradeState.Done));
        vm.expectRevert("Upgrade already exists");
        // Try second time
        handler.executeEmergencyUpgrade(proposal, new uint256[](0), true, true);
    }

    function test_unfreezeWithSpecificChains() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        // Create array with only first two chain IDs (simulating skipping one chain)
        uint256[] memory specificChains = new uint256[](2);
        specificChains[0] = chainIds[0];
        specificChains[1] = chainIds[1];

        // Expect calls only for the specified chains
        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[0])
        );
        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[1])
        );
        vm.expectCall(address(bridgeHub), abi.encodeWithSelector(IPausable.unpause.selector));
        vm.expectCall(address(l1AssetRouter), abi.encodeWithSelector(IPausable.unpause.selector));

        // Verify event with correct parameters
        vm.expectEmit(true, true, true, true);
        emit IProtocolUpgradeHandler.Unfreeze(specificChains, true);

        vm.prank(securityCouncil);
        handler.unfreeze(specificChains, false, true);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterSoftFreeze)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_unfreezeWithSpecificChainsAfterHardFreeze() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        vm.prank(securityCouncil);
        handler.unfreeze(specificChains, false, true);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterHardFreeze)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_unfreezeEmptyArrayQueriesBridgehub() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        // Empty array with _unfreezeAllChains=true queries Bridgehub and unfreezes ALL chains
        uint256[] memory emptyChains = new uint256[](0);

        // Expect getAllZKChainChainIDs to be called
        vm.expectCall(address(bridgeHub), abi.encodeWithSelector(IBridgeHub.getAllZKChainChainIDs.selector));

        // Expect calls for ALL chains (same as regular unfreeze)
        for (uint256 i = 0; i < chainIds.length; i++) {
            vm.expectCall(
                address(chainTypeManager),
                abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[i])
            );
        }
        vm.expectCall(address(bridgeHub), abi.encodeWithSelector(IPausable.unpause.selector));

        vm.prank(securityCouncil);
        handler.unfreeze(emptyChains, true, true);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterSoftFreeze)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_unfreezeAfterFreezeExpired() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        // Warp past the freeze period
        vm.warp(block.timestamp + 12 hours + 1);

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        // Anyone can call after freeze expired
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        handler.unfreeze(specificChains, false, true);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterSoftFreeze)
        );
    }

    function test_RevertWhen_unfreezeNotFrozen() public {
        _resetUpgradeCycle();

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        vm.prank(securityCouncil);
        vm.expectRevert("Unexpected last freeze status");
        handler.unfreeze(specificChains, false, true);
    }

    function test_RevertWhen_unfreezeUnauthorized() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        // Random caller should fail when protocol is still frozen
        address randomCaller = makeAddr("randomCaller");
        vm.prank(randomCaller);
        vm.expectRevert("Only Security Council is allowed to call this function or the protocol should be frozen");
        handler.unfreeze(specificChains, false, true);
    }

    function test_emergencyUpgradeDoesNotAutoUnfreeze() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);

        // Execute emergency upgrade
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("emergencyNoUnfreeze");
        proposal.executor = emergencyUpgradeBoard;

        vm.prank(emergencyUpgradeBoard);
        handler.executeEmergencyUpgrade(proposal, new uint256[](0), true, true);

        // Verify freeze state is cleared
        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.None)
        );
        assertEq(0, handler.protocolFrozenUntil());

        // Now we can call reinforceUnfreeze to actually unfreeze chains
        // (this would fail before because protocolFrozenUntil != 0)
        handler.reinforceUnfreeze(new uint256[](0), true, true);
    }

    function test_unfreezeWithUnpauseBridgesFalse() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[0])
        );
        vm.expectEmit(true, true, true, true);
        emit IProtocolUpgradeHandler.Unfreeze(specificChains, false);

        vm.prank(securityCouncil);
        handler.unfreeze(specificChains, false, false);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.AfterSoftFreeze)
        );
    }

    function test_reinforceUnfreezeWithSpecificChains() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);

        uint256[] memory specificChains = new uint256[](2);
        specificChains[0] = chainIds[0];
        specificChains[1] = chainIds[1];

        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[0])
        );
        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[1])
        );
        vm.expectEmit(true, true, true, true);
        emit IProtocolUpgradeHandler.ReinforceUnfreeze(specificChains, true);

        handler.reinforceUnfreeze(specificChains, false, true);
    }

    function test_executeEmergencyUpgradeWithSpecificChains() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("emergencySpecificChains");
        proposal.executor = emergencyUpgradeBoard;
        bytes32 id = keccak256(abi.encode(proposal));

        uint256[] memory specificChains = new uint256[](2);
        specificChains[0] = chainIds[0];
        specificChains[1] = chainIds[1];

        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[0])
        );
        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[1])
        );
        vm.expectCall(address(bridgeHub), abi.encodeWithSelector(IPausable.unpause.selector));
        vm.expectEmit(true, true, true, true);
        emit IProtocolUpgradeHandler.EmergencyUpgradeExecuted(id);

        vm.prank(emergencyUpgradeBoard);
        handler.executeEmergencyUpgrade(proposal, specificChains, false, true);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.None)
        );
        assertEq(0, handler.protocolFrozenUntil());
    }

    function test_executeEmergencyUpgradeWithUnpauseBridgesFalse() public {
        _resetUpgradeCycle();
        vm.prank(securityCouncil);
        handler.hardFreeze(new uint256[](0), true, true);

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("emergencyNoBridgeUnpause");
        proposal.executor = emergencyUpgradeBoard;

        uint256[] memory specificChains = new uint256[](1);
        specificChains[0] = chainIds[0];

        vm.expectCall(
            address(chainTypeManager),
            abi.encodeWithSelector(IChainTypeManager.unfreezeChain.selector, chainIds[0])
        );

        vm.prank(emergencyUpgradeBoard);
        handler.executeEmergencyUpgrade(proposal, specificChains, false, false);

        assertEq(
            uint256(handler.lastFreezeStatusInUpgradeCycle()),
            uint256(IProtocolUpgradeHandler.FreezeStatus.None)
        );
    }

    /// @notice Test that reinforceFreeze can be called multiple times with overlapping chain sets
    function test_reinforceFreezeWithOverlappingChains() public {
        // Setup: Soft freeze first
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        // First reinforceFreeze with chains [1, 300]
        uint256[] memory firstSet = new uint256[](2);
        firstSet[0] = chainIds[0]; // 1
        firstSet[1] = chainIds[1]; // 300

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceFreeze(firstSet, false);
        handler.reinforceFreeze(firstSet, false, false);

        // Second reinforceFreeze with chains [300, 324] (overlapping with chain 300)
        uint256[] memory secondSet = new uint256[](2);
        secondSet[0] = chainIds[1]; // 300 (overlap!)
        secondSet[1] = chainIds[2]; // 324

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceFreeze(secondSet, false);
        handler.reinforceFreeze(secondSet, false, false);

        // Third reinforceFreeze with all chains (complete overlap)
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceFreeze(chainIds, true);
        handler.reinforceFreeze(chainIds, false, true);

        // Verify protocol is still frozen
        assertEq(uint256(handler.lastFreezeStatusInUpgradeCycle()), uint256(IProtocolUpgradeHandler.FreezeStatus.Soft));
        assertGt(handler.protocolFrozenUntil(), block.timestamp);
    }

    /// @notice Test that reinforceUnfreeze can be called multiple times with overlapping chain sets
    function test_reinforceUnfreezeWithOverlappingChains() public {
        // Setup: Freeze and then unfreeze
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);

        // Protocol should be unfrozen now
        assertEq(handler.protocolFrozenUntil(), 0);

        // First reinforceUnfreeze with chains [1, 300]
        uint256[] memory firstSet = new uint256[](2);
        firstSet[0] = chainIds[0]; // 1
        firstSet[1] = chainIds[1]; // 300

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceUnfreeze(firstSet, false);
        handler.reinforceUnfreeze(firstSet, false, false);

        // Second reinforceUnfreeze with chains [300, 324] (overlapping with chain 300)
        uint256[] memory secondSet = new uint256[](2);
        secondSet[0] = chainIds[1]; // 300 (overlap!)
        secondSet[1] = chainIds[2]; // 324

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceUnfreeze(secondSet, false);
        handler.reinforceUnfreeze(secondSet, false, false);

        // Third reinforceUnfreeze with all chains (complete overlap)
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ReinforceUnfreeze(chainIds, true);
        handler.reinforceUnfreeze(chainIds, false, true);

        // Verify protocol is still unfrozen
        assertEq(handler.protocolFrozenUntil(), 0);
    }

    /// @notice Test that calling reinforceFreeze multiple times with same chains doesn't revert
    function test_reinforceFreezeSameChainsMultipleTimes() public {
        // Setup: Soft freeze first
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256[] memory sameChains = new uint256[](1);
        sameChains[0] = chainIds[0]; // chain 1

        // Call reinforceFreeze 5 times with the same chain
        for (uint256 i = 0; i < 5; i++) {
            handler.reinforceFreeze(sameChains, false, false);
        }

        // Should not revert and protocol should still be frozen
        assertEq(uint256(handler.lastFreezeStatusInUpgradeCycle()), uint256(IProtocolUpgradeHandler.FreezeStatus.Soft));
    }

    /// @notice Test that calling reinforceUnfreeze multiple times with same chains doesn't revert
    function test_reinforceUnfreezeSameChainsMultipleTimes() public {
        // Setup: Freeze and then unfreeze
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);

        uint256[] memory sameChains = new uint256[](1);
        sameChains[0] = chainIds[0]; // chain 1

        // Call reinforceUnfreeze 5 times with the same chain
        for (uint256 i = 0; i < 5; i++) {
            handler.reinforceUnfreeze(sameChains, false, false);
        }

        // Should not revert and protocol should still be unfrozen
        assertEq(handler.protocolFrozenUntil(), 0);
    }

    /// @notice Test that freeze reverts when explicitly specifying invalid chain ID
    function test_RevertWhen_freezeWithInvalidChainId() public {
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256 invalidChainId = 99999; // Non-existent chain
        uint256[] memory invalidChains = new uint256[](1);
        invalidChains[0] = invalidChainId;

        // Should revert with ChainTypeManagerNotFound
        vm.expectRevert(abi.encodeWithSelector(IProtocolUpgradeHandler.ChainTypeManagerNotFound.selector, invalidChainId));
        handler.reinforceFreeze(invalidChains, false, false);
    }

    /// @notice Test that unfreeze reverts when explicitly specifying invalid chain ID
    function test_RevertWhen_unfreezeWithInvalidChainId() public {
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, false);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, false);

        uint256 invalidChainId = 99999; // Non-existent chain
        uint256[] memory invalidChains = new uint256[](1);
        invalidChains[0] = invalidChainId;

        vm.expectRevert(abi.encodeWithSelector(IProtocolUpgradeHandler.ChainTypeManagerNotFound.selector, invalidChainId));
        handler.reinforceUnfreeze(invalidChains, false, false);
    }

    /// @notice Test that freeze reverts when trying to freeze zero chains
    function test_RevertWhen_freezeZeroChains() public {
        uint256[] memory emptyChains = new uint256[](0);

        vm.prank(securityCouncil);
        vm.expectRevert("Cannot freeze zero chains");
        handler.softFreeze(emptyChains, false, false);
    }

    /// @notice Test that unfreeze reverts when trying to unfreeze zero chains
    function test_RevertWhen_unfreezeZeroChains() public {
        // First freeze with all chains
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        vm.warp(block.timestamp + 1 hours);

        // Try to unfreeze zero chains
        uint256[] memory emptyChains = new uint256[](0);
        vm.prank(securityCouncil);
        vm.expectRevert("Cannot unfreeze zero chains");
        handler.unfreeze(emptyChains, false, false);
    }

    /// @notice Test that reinforceFreeze reverts when trying to freeze zero chains
    function test_RevertWhen_reinforceFreezeZeroChains() public {
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        uint256[] memory emptyChains = new uint256[](0);
        vm.expectRevert("Cannot freeze zero chains");
        handler.reinforceFreeze(emptyChains, false, false);
    }

    /// @notice Test that reinforceUnfreeze reverts when trying to unfreeze zero chains
    function test_RevertWhen_reinforceUnfreezeZeroChains() public {
        // First freeze and unfreeze with all chains
        vm.prank(securityCouncil);
        handler.softFreeze(new uint256[](0), true, true);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(securityCouncil);
        handler.unfreeze(new uint256[](0), true, true);

        // Try to reinforceUnfreeze zero chains
        uint256[] memory emptyChains = new uint256[](0);
        vm.expectRevert("Cannot unfreeze zero chains");
        handler.reinforceUnfreeze(emptyChains, false, false);
    }
}
