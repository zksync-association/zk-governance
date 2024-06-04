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

    struct TxRequest {
        address to;
        uint256 l2GasLimit;
        uint256 l2GasPerPubdataByteLimit;
        address refundRecipient;
        uint256 txMintValue;
    }

    function extendLegalVeto(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external;

    function approveUpgradeGuardians(bytes32 _id, address[] calldata _signers, bytes[] calldata _signatures) external;
}
