// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IGuardians {
    /// @dev Struct for L2 governor proposals parameters.
    /// @param targets Array of contract addresses to be called.
    /// @param values Array of ether values (in wei) to send with each call.
    /// @param calldatas Array of encoded function call data for each target.
    /// @param description Brief text or hash of the proposal for identification purposes.
    struct L2GovernorProposal {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        string description;
    }

    /// @dev Struct for L1 -> L2 transaction request parameters.
    /// @param to ZKsync address of the transaction recipient.
    /// @param l2GasLimit The maximum gas limit for executing this transaction on L2.
    /// @param l2GasPerPubdataByteLimit Limits the amount of gas per byte of public data on L2.
    /// @param refundRecipient The L2 address to which any refunds should be sent.
    /// @param txMintValue The ether minted on L2 in this L1 -> L2 transaction.
    struct TxRequest {
        address to;
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        address refundRecipient;
        uint256 txMintValue;
    }

    function extendLegalVeto(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external;

    function approveUpgradeGuardians(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external;

    function cancelL2GovernorProposal(
        L2GovernorProposal calldata _l2Proposal,
        TxRequest calldata _txRequest,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external payable;

    function proposeL2GovernorProposal(
        L2GovernorProposal calldata _l2Proposal,
        TxRequest calldata _txRequest,
        address[] calldata _signers,
        bytes[] calldata _signatures
    ) external payable;

    function hashL2Proposal(L2GovernorProposal calldata _l2Proposal) external pure returns (uint256 proposalId);
}
