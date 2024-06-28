// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {Callee} from "./utils/Callee.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {StateTransitionManagerMock} from "./mocks/StateTransitionManagerMock.t.sol";

import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "../../src/interfaces/IZKsyncEra.sol";
import {IStateTransitionManager} from "../../src/interfaces/IStateTransitionManager.sol";
import {IPausable} from "../../src/interfaces/IPausable.sol";

import {ProtocolUpgradeHandler} from "../../src/ProtocolUpgradeHandler.sol";

struct ZkSyncProofData {
    uint256 _l2BatchNumber;
    uint256 _l2MessageIndex;
    uint16 _l2TxNumberInBatch;
    bytes32[] _proof;
}

contract TestProtocolUpgradeHandler is Test {
    address securityCouncil;
    address guardians;
    address emergencyUpgradeBoard;
    address l2ProtocolGovernor;
    IZKsyncEra zksyncAddress;
    IStateTransitionManager stateTransitionManager;
    IPausable bridgeHub;
    IPausable sharedBridge;

    ProtocolUpgradeHandler handler;

    function _createProofData(IProtocolUpgradeHandler.UpgradeProposal memory _proposal, bool _isCorrect)
        internal
        returns (ZkSyncProofData memory)
    {
        uint256 batchNumber = 100;
        uint256 index = 0;
        uint16 txNumberInBatch = _isCorrect ? 10 : 11;
        bytes32[] memory proof = new bytes32[](11);
        bytes memory upgradeMessage = abi.encode(_proposal);

        IZKsyncEra.L2Message memory l2ToL1Message =
            IZKsyncEra.L2Message({txNumberInBatch: txNumberInBatch, sender: l2ProtocolGovernor, data: upgradeMessage});

        vm.mockCall(
            address(zksyncAddress),
            abi.encodeWithSelector(
                IZKsyncEra.proveL2MessageInclusion.selector, batchNumber, index, l2ToL1Message, proof
            ),
            abi.encode(_isCorrect)
        );

        return ZkSyncProofData(batchNumber, index, txNumberInBatch, proof);
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
        bytes32 _id
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
        vm.warp(block.timestamp + 1 days);
    }

    constructor() {
        securityCouncil = makeAddr("securityCouncil");
        guardians = makeAddr("guadians");
        emergencyUpgradeBoard = makeAddr("emergencyUpgradeBoard");
        l2ProtocolGovernor = makeAddr("l2ProtocolGovernor");
        zksyncAddress = IZKsyncEra(address(new EmptyContract()));
        stateTransitionManager = IStateTransitionManager(address(new StateTransitionManagerMock()));

        bridgeHub = IPausable(address(new EmptyContract()));
        sharedBridge = IPausable(address(new EmptyContract()));

        handler = new ProtocolUpgradeHandler(
            securityCouncil,
            guardians,
            emergencyUpgradeBoard,
            l2ProtocolGovernor,
            zksyncAddress,
            stateTransitionManager,
            bridgeHub,
            sharedBridge
        );
    }

    function test_constructorEvents() public {
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeSecurityCouncil(address(0), securityCouncil);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeGuardians(address(0), guardians);
        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.ChangeEmergencyUpgradeBoard(address(0), emergencyUpgradeBoard);

        ProtocolUpgradeHandler testHandler = new ProtocolUpgradeHandler(
            securityCouncil,
            guardians,
            emergencyUpgradeBoard,
            l2ProtocolGovernor,
            zksyncAddress,
            stateTransitionManager,
            bridgeHub,
            sharedBridge
        );
        assertEq(testHandler.securityCouncil(), securityCouncil);
        assertEq(testHandler.guardians(), guardians);
        assertEq(testHandler.emergencyUpgradeBoard(), emergencyUpgradeBoard);
        assertEq(testHandler.L2_PROTOCOL_GOVERNOR(), l2ProtocolGovernor);
        assertEq(address(testHandler.ZKSYNC_ERA()), address(zksyncAddress));
        assertEq(address(testHandler.STATE_TRANSITION_MANAGER()), address(stateTransitionManager));
        assertEq(address(testHandler.BRIDGE_HUB()), address(bridgeHub));
        assertEq(address(testHandler.SHARED_BRIDGE()), address(sharedBridge));
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
        // It is assumed that zkSync Era has completely correctly implemented message proving, i.e. we will consider
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
        vm.warp(block.timestamp + 1 days);
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

    function testApproveUpgradeGuardiansOnlyGuardians() public {
        vm.expectRevert("Only guardians is allowed to call this function");
        handler.approveUpgradeGuardians(bytes32(uint256(0x01)));
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

        vm.warp(block.timestamp + 1 days);
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

        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, false, false, true);
        emit IProtocolUpgradeHandler.UpgradeExecuted(id);
        handler.execute(proposal);
    }

    function testExecuteMsgSenderAuthorized(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil
    ) public {
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = _emptyProposal("23");
        proposal.executor = makeAddr("executor");
        bytes32 id = _startUpgrade(proposal);
        _makeUpgradeReady(_extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id);

        vm.expectRevert("msg.sender is not authorized to perform the upgrade");
        handler.execute(proposal);

        vm.prank(proposal.executor);
        handler.execute(proposal);
    }

    function testExecuteReentrancy(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil
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
        _makeUpgradeReady(_extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id);
        vm.expectRevert("Upgrade is not yet ready");
        handler.execute(proposal);
    }

    function testExecuteCorrectData(
        bool _extendedLegalPeriod,
        bool _approvedByGuardians,
        bool _approvedBySecurityCouncil
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
        _makeUpgradeReady(_extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id);

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
        bool _approvedBySecurityCouncil
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
        _makeUpgradeReady(_extendedLegalPeriod, _approvedByGuardians, _approvedBySecurityCouncil, id);
        handler.execute(proposal);

        assertEq(handler.securityCouncil(), newSecurityCouncil);
        assertEq(handler.guardians(), newGuardians);
    }

    function test_Receive() public {
        address randomAddress = address(0x1000);
        vm.deal(address(randomAddress), 1 ether);
        vm.prank(randomAddress);
        payable(handler).send(1 ether);
    }
}
