// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

contract Callee {
    uint256[] recordedValues;
    bytes[] recordedCalldatas;

    bytes calldataForReentrancy;

    function setCalldataForReentrancy(bytes calldata _newData) external {
        calldataForReentrancy = _newData;
    }

    function getRecordedValues() external returns (uint256[] memory values) {
        values = recordedValues;
    }

    function getRecordedCalldatas() external returns (bytes[] memory values) {
        values = recordedCalldatas;
    }

    // Typically the ProtocolUpgradeHandler will only call trusted contracts, but just in case we simulate a bad actor
    function reenterCaller() external {
        (bool success,) = address(msg.sender).call(calldataForReentrancy);
        if (!success) {
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }

    fallback() external payable {
        recordedValues.push(msg.value);
        recordedCalldatas.push(msg.data);
    }

    // add this to be excluded from coverage report
    function test() internal virtual {}
}
