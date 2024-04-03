// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IZkSyncEra {
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

    function proveL2MessageInclusion(
        uint256 _batchNumber,
        uint256 _index,
        L2Message memory _message,
        bytes32[] calldata _proof
    ) external view returns (bool);
}
