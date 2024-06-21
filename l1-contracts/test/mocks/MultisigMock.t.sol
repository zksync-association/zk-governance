// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Multisig} from "../../src/Multisig.sol";

contract MultisigMock is Multisig {
    constructor(address[] memory _members, uint256 _eip1271Threshold) Multisig(_members, _eip1271Threshold) {}

    function getMembers() external view returns (address[] memory) {
        return members;
    }

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
