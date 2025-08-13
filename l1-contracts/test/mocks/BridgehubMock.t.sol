// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract BridgehubMock {
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

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
