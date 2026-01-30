// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IBridgeHub, L2TransactionRequestDirect} from "../../src/interfaces/IBridgeHub.sol";

contract BridgehubMock is IBridgeHub {
  uint256[] chainIds;

  constructor(uint256[] memory _chainIds) {
    chainIds = _chainIds;
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
    L2Message calldata _message,
    bytes32[] calldata _proof
  ) external view returns (bool) {
    return true;
  }

  // add this to be excluded from coverage report
  function test() internal virtual {}
}
