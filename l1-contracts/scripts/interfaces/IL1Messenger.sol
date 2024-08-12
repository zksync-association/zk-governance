// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IL1Messenger {
    function sendToL1(bytes memory _message) external returns (bytes32);
}
