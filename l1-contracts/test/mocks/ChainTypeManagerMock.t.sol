// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract ChainTypeManagerMock {
    uint256[] chainIds;

    constructor(uint256[] memory _chainIds) {
        chainIds = _chainIds;
    }

    function freezeChain(uint256 _chainId) external {
        for (uint256 i = 0; i < chainIds.length; i++) {
            if (_chainId == chainIds[i]) {
                return;
            }
        }
        revert();
    }

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
