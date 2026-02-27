// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";

contract TestnetRedeploy is Redeploy {
    address public PUH_PROXY_TESTNET = vm.envAddress("PUH_PROXY_TESTNET");

    function run() external {
        runRedeploy(
            PUH_PROXY_TESTNET, 
            true
        );
    }
}
