// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

contract MainnetRedeploy is Redeploy {
    function run() external {
        runRedeploy(
            0x8f7a9912416e8AdC4D9c21FAe1415D3318A11897, 
            false
        );
    }
}
