// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

contract MainnetRedeploy is Redeploy {
    address public PUH_PROXY_MAINNET = vm.envAddress("PUH_PROXY_MAINNET");

    function run() external {
        runRedeploy(
            PUH_PROXY_MAINNET,
            false
        );
    }
}
