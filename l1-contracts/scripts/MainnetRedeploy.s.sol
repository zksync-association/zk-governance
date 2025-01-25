// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Redeploy} from "./Redeploy.s.sol";

import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

contract MainnetRedeploy is Redeploy {
    function run() external {
        runRedeploy(
            0x8f7a9912416e8adc4d9c21fae1415d3318a11897, 
            0x32400084c286cf3e17e7b677ea9583e60a000324, 
            0xc2eE6b6af7d616f6e27ce7F4A451Aedc2b0F5f5C, 
            0x303a465B659cBB0ab36eE643eA362c509EEb5213, 
            0xD7f9f54194C633F36CCD5F3da84ad4a1c38cB2cB, 
            type(ProtocolUpgradeHandler).creationCode
        );
    }
}
