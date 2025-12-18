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
    function requestL2TransactionDirect(L2TransactionRequestDirect calldata _request)
        external
        payable
        returns (bytes32 canonicalTxHash);

    function getAllZKChainChainIDs() external view returns (uint256[] memory);
}
