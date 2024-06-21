// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";

contract GovernorMock is Governor {
    // add this to be excluded from coverage report
    function test() internal virtual {}

    constructor() Governor("") {}

    // We don't need to truly implement the missing functions because we are just testing
    // internal helpers.

    function clock() public pure override returns (uint48) {}

    function CLOCK_MODE() public pure override returns (string memory) {}

    function COUNTING_MODE() public pure virtual override returns (string memory) {}

    function votingDelay() public pure virtual override returns (uint256) {}

    function votingPeriod() public pure virtual override returns (uint256) {}

    function quorum(uint256) public pure virtual override returns (uint256) {}

    function hasVoted(uint256, address) public pure virtual override returns (bool) {}

    function _quorumReached(uint256) internal pure virtual override returns (bool) {}

    function _voteSucceeded(uint256) internal pure virtual override returns (bool) {}

    function _getVotes(address, uint256, bytes memory) internal pure virtual override returns (uint256) {}

    function _countVote(uint256, address, uint8, uint256, bytes memory) internal virtual override {}
}
