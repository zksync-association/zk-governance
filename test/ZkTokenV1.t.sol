// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";

contract ZkTokenV1Test is Test {
  ZkTokenV1 token;
  address proxyOwner = makeAddr("Proxy Owner");

  function setUp() public {
    address _proxy =
      Upgrades.deployTransparentProxy("ZkTokenV1.sol", proxyOwner, abi.encodeCall(ZkTokenV1.initialize, ()));

    token = ZkTokenV1(_proxy);
  }
}

contract Initialize is ZkTokenV1Test {
  function test_InitializesTheTokenWithTheCorrectNameAndSymbolWhenDeployedViaUpgrades() public {
    assertEq(token.symbol(), "ZK");
    assertEq(token.name(), "zkSync");
  }

  function test_InitializesTheTokenWithTheCorrectNameAndSymbolWhenCalledDirectly() public {
    ZkTokenV1 _token = new ZkTokenV1();
    _token.initialize();

    assertEq(_token.symbol(), "ZK");
    assertEq(_token.name(), "zkSync");
  }
}
