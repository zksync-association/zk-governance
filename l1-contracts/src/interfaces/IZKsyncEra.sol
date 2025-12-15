// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IZKsyncEra {
    /// @dev An arbitrary length message passed from L2
    /// @notice Under the hood it is `L2Log` sent from the special system L2 contract
    /// @param txNumberInBatch The L2 transaction number in the batch, in which the message was sent
    /// @param sender The address of the L2 account from which the message was passed
    /// @param data An arbitrary length message
    struct L2Message {
        uint16 txNumberInBatch;
        address sender;
        bytes data;
    }

    /// @notice Prove that a specific arbitrary-length message was sent in a specific L2 batch number
    /// @param _batchNumber The executed L2 batch number in which the message appeared
    /// @param _index The position in the L2 logs Merkle tree of the l2Log that was sent with the message
    /// @param _message Information about the sent message: sender address, the message itself, tx index in the L2 batch where the message was sent
    /// @param _proof Merkle proof for inclusion of L2 log that was sent with the message
    /// @return Whether the proof is valid
    function proveL2MessageInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Message memory _message,
        bytes32[] calldata _proof
    ) external view returns (bool);

    /// @notice Estimates the cost in Ether of requesting execution of an L2 transaction from L1
    /// @param _gasPrice expected L1 gas price at which the user requests the transaction execution
    /// @param _l2GasLimit Maximum amount of L2 gas that transaction can consume during execution on L2
    /// @param _l2GasPerPubdataByteLimit The maximum amount of L2 gas that the operator may charge the user for a single byte of pubdata.
    /// @return The estimated ETH spent on L2 gas for the transaction
    function l2TransactionBaseCost(
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) external view returns (uint256);
}
