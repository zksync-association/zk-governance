// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";

contract TestnetRedeploy is Redeploy {
    function run() external {
        runRedeploy(
            0x9B956d242e6806044877C7C1B530D475E371d544, 
            0x9A6DE0f62Aa270A8bCB1e2610078650D539B1Ef9, 
            0x4e39E90746A9ee410A8Ce173C7B96D3AfEd444a5, 
            0x35A54c8C757806eB6820629bc82d90E056394C92, 
            0x3E8b2fe58675126ed30d0d12dea2A9bda72D18Ae, 
            type(TestnetProtocolUpgradeHandler).creationCode
        );
    }
}
