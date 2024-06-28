// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract StateTransitionManagerMock {
    function getAllHyperchainChainIDs() external view returns (uint256[] memory) {
        return new uint256[](0);
    }

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
