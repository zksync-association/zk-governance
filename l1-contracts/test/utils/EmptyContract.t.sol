// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract EmptyContract {
    fallback() external payable {}

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
