// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.t.sol";
import {EIP712Util} from "./utils/EIP712Util.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {GovernorMock} from "./mocks/GovernorMock.t.sol";
import {Guardians} from "../../src/Guardians.sol";
import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IGuardians} from "../../src/interfaces/IGuardians.sol";
import {IZKsyncEra} from "../../src/interfaces/IZKsyncEra.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract TestGuardians is Test, EIP712Util {
    IProtocolUpgradeHandler protocolUpgradeHandler = IProtocolUpgradeHandler(address(new EmptyContract()));
    IZKsyncEra zksyncAddress = IZKsyncEra(address(new EmptyContract()));
    Guardians guardians;
    Vm.Wallet[] wallets;
    address[] internal members;
    bytes32 internal guardiansDomainHash;

    /// @dev EIP-712 TypeHash for extending the legal veto period by the guardians.
    bytes32 internal constant EXTEND_LEGAL_VETO_PERIOD_TYPEHASH = keccak256("ExtendLegalVetoPeriod(bytes32 id)");

    /// @dev EIP-712 TypeHash for protocol upgrades approval by the guardians.
    bytes32 internal constant APPROVE_UPGRADE_GUARDIANS_TYPEHASH = keccak256("ApproveUpgradeGuardians(bytes32 id)");

    /// @dev EIP-712 TypeHash for canceling the L2 proposals by the guardians.
    bytes32 internal constant CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH = keccak256(
        "CancelL2GovernorProposal(uint256 l2ProposalId,address l2GovernorAddress,uint256 l2GasLimit,uint256 l2GasPerPubdataByteLimit,address refundRecipient,uint256 txMintValue,uint256 nonce)"
    );

    /// @dev EIP-712 TypeHash for proposing the L2 proposals by the guardians.
    bytes32 internal constant PROPOSE_L2_GOVERNOR_PROPOSAL_TYPEHASH = keccak256(
        "ProposeL2GovernorProposal(uint256 l2ProposalId,address l2GovernorAddress,uint256 l2GasLimit,uint256 l2GasPerPubdataByteLimit,address refundRecipient,uint256 txMintValue,uint256 nonce)"
    );

    constructor() {
        Vm.Wallet[] memory wallets_ = new Vm.Wallet[](8);
        for (uint256 i = 0; i < 8; i++) {
            wallets_[i] = vm.createWallet(string(abi.encodePacked("Account: ", i)));
        }
        wallets_ = Utils.sortWalletsByAddress(wallets_);

        for (uint256 i = 0; i < 8; i++) {
            wallets.push(wallets_[i]);
            members.push(wallets_[i].addr);
        }

        guardians = new Guardians(protocolUpgradeHandler, zksyncAddress, members);
        guardiansDomainHash = _buildDomainHash(address(guardians), "Guardians", "1");
    }

    function test_RevertWhen_NotEightMembers(uint256 _numberOfMembers) public {
        _numberOfMembers = bound(_numberOfMembers, 0, 100);
        vm.assume(_numberOfMembers != 8);
        address[] memory members_ = new address[](_numberOfMembers);

        for (uint256 i = 0; i < _numberOfMembers; i++) {
            members_[i] = address(uint160(i + 1));
        }

        if (_numberOfMembers >= 5) {
            vm.expectRevert("Guardians requires exactly 8 members");
        } else {
            vm.expectRevert("EIP-1271 threshold is too big");
        }

        new Guardians(protocolUpgradeHandler, zksyncAddress, members_);
    }

    function test_hashL2ProposalIsTheSameAsOnL2Governor(IGuardians.L2GovernorProposal memory _l2Proposal) public {
        GovernorMock l2Governor = new GovernorMock();
        uint256 l2GovernorHashProposal = l2Governor.hashProposal(
            _l2Proposal.targets, _l2Proposal.values, _l2Proposal.calldatas, keccak256(bytes(_l2Proposal.description))
        );
        uint256 l1GuardiansHashProposal = uint256(guardians.hashL2Proposal(_l2Proposal));
        assertEq(l2GovernorHashProposal, l1GuardiansHashProposal);
    }

    function test_RevertWhen_extendLegalVetoNotEnoughSigners(bytes32 _id, uint256 _numberOfSignatures) public {
        _numberOfSignatures = bound(_numberOfSignatures, 0, 1);
        address[] memory signers = new address[](_numberOfSignatures);
        bytes[] memory signatures = new bytes[](_numberOfSignatures);

        vm.expectRevert("Insufficient valid signatures");
        guardians.extendLegalVeto(_id, signers, signatures);
    }

    function test_RevertWhen_approveUpgradeGuardiansNotEnoughSigners(bytes32 _id, uint256 _numberOfSignatures) public {
        _numberOfSignatures = bound(_numberOfSignatures, 0, 4);
        address[] memory signers = new address[](_numberOfSignatures);
        bytes[] memory signatures = new bytes[](_numberOfSignatures);

        vm.expectRevert("Insufficient valid signatures");
        guardians.approveUpgradeGuardians(_id, signers, signatures);
    }

    function test_RevertWhen_cancelL2GovernorProposalNotEnoughSigners(
        IGuardians.L2GovernorProposal memory _l2Proposal,
        IGuardians.TxRequest memory _txRequest,
        uint256 _numberOfSignatures
    ) public {
        _numberOfSignatures = bound(_numberOfSignatures, 0, 4);
        address[] memory signers = new address[](_numberOfSignatures);
        bytes[] memory signatures = new bytes[](_numberOfSignatures);

        vm.expectRevert("Insufficient valid signatures");
        guardians.cancelL2GovernorProposal(_l2Proposal, _txRequest, signers, signatures);
    }

    function test_RevertWhen_proposeL2GovernorProposalNotEnoughSigners(
        IGuardians.L2GovernorProposal memory _l2Proposal,
        IGuardians.TxRequest memory _txRequest,
        uint256 _numberOfSignatures
    ) public {
        _numberOfSignatures = bound(_numberOfSignatures, 0, 4);
        address[] memory signers = new address[](_numberOfSignatures);
        bytes[] memory signatures = new bytes[](_numberOfSignatures);

        vm.expectRevert("Insufficient valid signatures");
        guardians.proposeL2GovernorProposal(_l2Proposal, _txRequest, signers, signatures);
    }

    function test_extendLegalVeto(bytes32 _id, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask) public {
        _numberOfSignatures = bound(_numberOfSignatures, 2, 8);

        bytes32 message = keccak256(abi.encode(EXTEND_LEGAL_VETO_PERIOD_TYPEHASH, _id));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        guardians.extendLegalVeto(_id, signers, signatures);
    }

    function test_approveUpgradeGuardians(bytes32 _id, uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask)
        public
    {
        _numberOfSignatures = bound(_numberOfSignatures, 5, 8);

        bytes32 message = keccak256(abi.encode(APPROVE_UPGRADE_GUARDIANS_TYPEHASH, _id));
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        guardians.approveUpgradeGuardians(_id, signers, signatures);
    }

    function test_cancelL2GovernorProposal(
        IGuardians.L2GovernorProposal memory _l2Proposal,
        IGuardians.TxRequest memory _txRequest,
        uint256 _numberOfSignatures,
        uint256 _isEOAOrEIP712Mask
    ) public payable {
        _numberOfSignatures = bound(_numberOfSignatures, 5, 8);
        _txRequest.txMintValue = bound(_txRequest.txMintValue, 0, 100 ether);

        uint256 nonceBefore = guardians.nonce();
        bytes32 message = keccak256(
            abi.encode(
                CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH,
                guardians.hashL2Proposal(_l2Proposal),
                _txRequest.to,
                _txRequest.l2GasLimit,
                _txRequest.l2GasPerPubdataByteLimit,
                _txRequest.refundRecipient,
                _txRequest.txMintValue,
                nonceBefore
            )
        );
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        guardians.cancelL2GovernorProposal{value: _txRequest.txMintValue}(_l2Proposal, _txRequest, signers, signatures);
        assertEq(guardians.nonce(), nonceBefore + 1);
    }

    function test_proposeL2Proposal(
        IGuardians.L2GovernorProposal memory _l2Proposal,
        IGuardians.TxRequest memory _txRequest,
        uint256 _numberOfSignatures,
        uint256 _isEOAOrEIP712Mask
    ) public payable {
        _numberOfSignatures = bound(_numberOfSignatures, 5, 8);
        _txRequest.txMintValue = bound(_txRequest.txMintValue, 0, 100 ether);

        uint256 nonceBefore = guardians.nonce();
        bytes32 message = keccak256(
            abi.encode(
                PROPOSE_L2_GOVERNOR_PROPOSAL_TYPEHASH,
                guardians.hashL2Proposal(_l2Proposal),
                _txRequest.to,
                _txRequest.l2GasLimit,
                _txRequest.l2GasPerPubdataByteLimit,
                _txRequest.refundRecipient,
                _txRequest.txMintValue,
                nonceBefore
            )
        );
        (address[] memory signers, bytes[] memory signatures) =
            _prepareSignersAndSignatures(_numberOfSignatures, _isEOAOrEIP712Mask, message);

        guardians.proposeL2GovernorProposal{value: _txRequest.txMintValue}(_l2Proposal, _txRequest, signers, signatures);
        assertEq(guardians.nonce(), nonceBefore + 1);
    }

    function _prepareSignersAndSignatures(uint256 _numberOfSignatures, uint256 _isEOAOrEIP712Mask, bytes32 _message)
        internal
        returns (address[] memory signers, bytes[] memory signatures)
    {
        signers = new address[](_numberOfSignatures);
        signatures = new bytes[](_numberOfSignatures);
        bytes32 digest = _buildDigest(guardiansDomainHash, _message);
        for (uint256 i = 0; i < _numberOfSignatures; i++) {
            signers[i] = members[i];
            if ((_isEOAOrEIP712Mask & (1 << i)) != 0) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallets[i].privateKey, digest);
                signatures[i] = abi.encodePacked(r, s, v);
            } else {
                _mockEip712Call(signers[i], digest);
            }
        }
    }

    function _mockEip712Call(address _signer, bytes32 _digest) private {
        vm.mockCall(
            _signer,
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, _digest),
            abi.encode(IERC1271.isValidSignature.selector)
        );
    }
}
