// SPDX-License-Identifier: MIT

import {IBridgeHub, L2TransactionRequestDirect} from "../../src/interfaces/IBridgeHub.sol";

pragma solidity 0.8.24;

contract BridgehubMock {
    uint256[] chainIds;
    mapping(uint256 chainId => address) public chainTypeManager;

    constructor(uint256[] memory _chainIds) {
        chainIds = _chainIds;
    }

    function setChainTypeManager(uint256 _chainId, address _chainTypeManager) external {
        chainTypeManager[_chainId] = _chainTypeManager;
    }

    function getAllZKChainChainIDs() external view returns (uint256[] memory) {
        return chainIds;
    }

    function pause() external {
        // Do nothing
    }
    
    function unpause() external {
        // Do nothing
    }

    function requestL2TransactionDirect(L2TransactionRequestDirect calldata _request)
        external
        payable
        returns (bytes32 canonicalTxHash)
    {
        bytes32 canonicalTxHash;
    }

    function proveL2MessageInclusion(
        uint256 _chainId,
        uint256 _batchNumber,
        uint256 _index,
        IBridgeHub.L2Message calldata _message,
        bytes32[] calldata _proof
    ) external view returns (bool) {
        return true;
    }    

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
