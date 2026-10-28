// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

// Logging helpers shared by the protocol upgrade governance scripts in both l2-contracts projects. It uses only plain
// types, so it compiles under the main project's solc 0.8.24 and the council project's solc 0.8.30.
abstract contract DeployBase is Script {
  bool internal isLogging = true;

  // Silences the script's output, for tests that run it.
  function disableLogging() public {
    isLogging = false;
  }

  function _log(string memory _message) internal view {
    if (isLogging) {
      console2.log(_message);
    }
  }

  function _eq(string memory _a, string memory _b) internal pure returns (bool) {
    return keccak256(bytes(_a)) == keccak256(bytes(_b));
  }
}
