// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV2} from "src/ZkTokenV2.sol";

contract ZkTokenUpgradeFake is ZkTokenV2 {
  function initializeFake() external reinitializer(3) {
    __ERC20_init("ZKsyncFake", "ZK");
    __ERC20Permit_init("ZKsyncFake");
  }
}
