// SPDX-License-Identifier: MIT

import {IPausable} from "./IPausable.sol";

struct L2TransactionRequestDirect {
    uint256 chainId;
    uint256 mintValue;
    address l2Contract;
    uint256 l2Value;
    bytes l2Calldata;
    uint256 l2GasLimit;
    uint256 l2GasPerPubdataByteLimit;
    bytes[] factoryDeps;
    address refundRecipient;
}

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IBridgeHub is IPausable {
    /// @dev An arbitrary length message passed from L2
    /// @notice Under the hood it is `L2Log` sent from the special system L2 contract
    /// @param txNumberInBatch The L2 transaction number in a Batch, in which the message was sent
    /// @param sender The address of the L2 account from which the message was passed
    /// @param data An arbitrary length message
    struct L2Message {
        uint16 txNumberInBatch;
        address sender;
        bytes data;
    }

    /// @notice The mailbox is called directly after the assetRouter received the deposit
    /// this assumes that either ether is the base token or
    /// the msg.sender has approved mintValue allowance for the nativeTokenVault.
    /// This means this is not ideal for contract calls, as the contract would have to handle token allowance of the base Token.
    /// In case allowance is provided to the Asset Router, then it will be transferred to NTV.
    function requestL2TransactionDirect(L2TransactionRequestDirect calldata _request)
        external
        payable
        returns (bytes32 canonicalTxHash);

    /// @notice Returns all the registered zkChain chainIDs
    function getAllZKChainChainIDs() external view returns (uint256[] memory);

    /// @notice forwards function call to Mailbox based on ChainId
    /// @param _chainId The chain ID of the ZK chain where to prove L2 message inclusion.
    /// @param _batchNumber The executed L2 batch number in which the message appeared
    /// @param _index The position in the L2 logs Merkle tree of the l2Log that was sent with the message
    /// @param _message Information about the sent message: sender address, the message itself, tx index in the L2 batch where the message was sent
    /// @param _proof Merkle proof for inclusion of L2 log that was sent with the message
    /// @return Whether the proof is valid
    function proveL2MessageInclusion(
        uint256 _chainId,
        uint256 _batchNumber,
        uint256 _index,
        L2Message calldata _message,
        bytes32[] calldata _proof
    ) external view returns (bool);
}
