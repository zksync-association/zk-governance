// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IGuardians} from "./interfaces/IGuardians.sol";
import {IZKsyncEra} from "./interfaces/IZKsyncEra.sol";
import {IL2Governor} from "./interfaces/IL2Governor.sol";
import {IProtocolUpgradeHandler} from "./interfaces/IProtocolUpgradeHandler.sol";
import {Multisig} from "./Multisig.sol";

/// @title Guadians
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev Temporary protector of the values of ZKsync. They can approve upgrade changes proposed by the Token Assembly, propose & cancel
/// L2 proposals as well as extend the legal veto period of L1 upgrade proposals through the `ProtocolUpgradeHandler`.
contract Guardians is IGuardians, Multisig, EIP712 {
    /// @notice Address of the contract, which manages protocol upgrades.
    IProtocolUpgradeHandler public immutable PROTOCOL_UPGRADE_HANDLER;

    /// @dev ZKsync smart contract that used to operate with L2 via asynchronous L2 <-> L1 communication.
    IZKsyncEra public immutable ZKSYNC_ERA;

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

    /// @dev The number of signatures needed to approve the upgrade by guardians.
    uint256 public constant APPROVE_UPGRADE_GUARDIANS_THRESHOLD = 5;

    /// @dev The number of signatures needed to extend the legal veto period for the upgrade.
    uint256 public constant EXTEND_LEGAL_VETO_THRESHOLD = 2;

    /// @dev The number of signatures needed to cancel the proposal on one of the L2 Governors.
    uint256 public constant CANCEL_L2_GOVERNOR_PROPOSAL_THRESHOLD = 5;

    /// @dev The number of signatures needed to propose the proposal on one of the L2 Governors.
    uint256 public constant PROPOSE_L2_GOVERNOR_PROPOSAL_THRESHOLD = 5;

    /// @dev Tracks the unique identifier used in the last `cancelL2GovernorProposal`/`proposeL2GovernorProposal` to ensure replay attack protection.
    uint256 public nonce;

    /// @dev Initializes the Guardians contract with predefined members and setup for EIP-712.
    /// @param _protocolUpgradeHandler The address of the protocol upgrade handler contract, responsible for executing the upgrades.
    /// @param _members Array of addresses representing the members of the guardians.
    /// Expected to be sorted in ascending order without duplicates.
    constructor(IProtocolUpgradeHandler _protocolUpgradeHandler, IZKsyncEra _ZKsyncEra, address[] memory _members)
        Multisig(_members, 5)
        EIP712("Guardians", "1")
    {
        PROTOCOL_UPGRADE_HANDLER = _protocolUpgradeHandler;
        ZKSYNC_ERA = _ZKsyncEra;
        require(_members.length == 8, "Guardians requires exactly 8 members");
    }

    /// @notice Extends legal veto period for ZKsync protocol upgrade, by the 2 out of 8 Guardians approvals.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the extend.
    function extendLegalVeto(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(EXTEND_LEGAL_VETO_PERIOD_TYPEHASH, _id)));
        checkSignatures(digest, _signers, _signatures, EXTEND_LEGAL_VETO_THRESHOLD);
        PROTOCOL_UPGRADE_HANDLER.extendLegalVeto(_id);
    }

    /// @notice Approves ZKsync protocol upgrade, by the 5 out of 8 Guardians approvals.
    /// @param _id The unique identifier of the upgrade proposal.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    function approveUpgradeGuardians(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(APPROVE_UPGRADE_GUARDIANS_TYPEHASH, _id)));
        checkSignatures(digest, _signers, _signatures, APPROVE_UPGRADE_GUARDIANS_THRESHOLD);
        PROTOCOL_UPGRADE_HANDLER.approveUpgradeGuardians(_id);
    }

    /// @notice Cancel ZKsync proposal in one of the L2 governors, by the 5 of 8 Guardians approvals.
    /// @param _l2Proposal The L2 governor proposal to be canceled.
    /// @param _txRequest The L1 -> L2 transaction parameters needed to request execution on L2.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    function cancelL2GovernorProposal(
        L2GovernorProposal calldata _l2Proposal,
        TxRequest calldata _txRequest,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external payable {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CANCEL_L2_GOVERNOR_PROPOSAL_TYPEHASH,
                    hashL2Proposal(_l2Proposal),
                    _txRequest.to,
                    _txRequest.l2GasLimit,
                    _txRequest.l2GasPerPubdataByteLimit,
                    _txRequest.refundRecipient,
                    _txRequest.txMintValue,
                    nonce++
                )
            )
        );
        checkSignatures(digest, _signers, _signatures, CANCEL_L2_GOVERNOR_PROPOSAL_THRESHOLD);
        bytes memory cancelCalldata = abi.encodeCall(
            IL2Governor.cancel,
            (_l2Proposal.targets, _l2Proposal.values, _l2Proposal.calldatas, keccak256(bytes(_l2Proposal.description)))
        );
        ZKSYNC_ERA.requestL2Transaction{value: _txRequest.txMintValue}(
            _txRequest.to,
            0,
            cancelCalldata,
            _txRequest.l2GasLimit,
            _txRequest.l2GasPerPubdataByteLimit,
            new bytes[](0),
            _txRequest.refundRecipient
        );
    }

    /// @notice Propose ZKsync proposal on one the L2 governors, by the 5 of 8 Guardians approvals.
    /// @param _l2Proposal The L2 governor proposal to be proposed.
    /// @param _txRequest The L1 -> L2 transaction parameters needed to request execution on L2.
    /// @param _signers An array of signers associated with the signatures.
    /// @param _signatures An array of signatures from the guardians approving the upgrade.
    function proposeL2GovernorProposal(
        L2GovernorProposal calldata _l2Proposal,
        TxRequest calldata _txRequest,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external payable {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    PROPOSE_L2_GOVERNOR_PROPOSAL_TYPEHASH,
                    hashL2Proposal(_l2Proposal),
                    _txRequest.to,
                    _txRequest.l2GasLimit,
                    _txRequest.l2GasPerPubdataByteLimit,
                    _txRequest.refundRecipient,
                    _txRequest.txMintValue,
                    nonce++
                )
            )
        );
        checkSignatures(digest, _signers, _signatures, PROPOSE_L2_GOVERNOR_PROPOSAL_THRESHOLD);
        bytes memory proposeCalldata = abi.encodeCall(
            IL2Governor.propose,
            (_l2Proposal.targets, _l2Proposal.values, _l2Proposal.calldatas, _l2Proposal.description)
        );
        ZKSYNC_ERA.requestL2Transaction{value: _txRequest.txMintValue}(
            _txRequest.to,
            0,
            proposeCalldata,
            _txRequest.l2GasLimit,
            _txRequest.l2GasPerPubdataByteLimit,
            new bytes[](0),
            _txRequest.refundRecipient
        );
    }

    /// @return proposalId The unique identifier for the L2 proposal in compatible format with L2 Governors.
    function hashL2Proposal(L2GovernorProposal calldata _l2Proposal) public pure returns (uint256 proposalId) {
        proposalId = uint256(
            keccak256(
                abi.encode(
                    _l2Proposal.targets,
                    _l2Proposal.values,
                    _l2Proposal.calldatas,
                    keccak256(bytes(_l2Proposal.description))
                )
            )
        );
    }
}
