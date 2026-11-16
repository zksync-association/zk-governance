// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";

abstract contract TestHelpers is Test {
  // Counts the recorded logs a given contract emitted. EraVM's system contracts emit their own logs on every call, so
  // only the contract's own logs are counted.
  function _countLogsEmittedBy(address _emitter) internal returns (uint256 _count) {
    Vm.Log[] memory _logs = vm.getRecordedLogs();
    for (uint256 _i = 0; _i < _logs.length; _i += 1) {
      if (_logs[_i].emitter == _emitter) {
        _count += 1;
      }
    }
  }

  // Excludes the addresses below 0x10000, where EraVM keeps its system contracts and precompiles.
  function _assumeNotASystemAddress(address _account) internal pure {
    vm.assume(uint160(_account) > 0xFFFF);
  }
}
