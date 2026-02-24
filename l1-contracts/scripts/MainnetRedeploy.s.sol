// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

contract MainnetRedeploy is Redeploy {
    address public constant PUH_PROXY = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;

    function run() external {
        runRedeploy(
            PUH_PROXY,
            false
        );
    }
}
