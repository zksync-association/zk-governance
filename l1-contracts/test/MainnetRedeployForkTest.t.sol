// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, stdStorage, StdStorage} from "forge-std/Test.sol";

import {Callee} from "./utils/Callee.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {StateTransitionManagerMock} from "./mocks/StateTransitionManagerMock.t.sol";

import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "../../src/interfaces/IZKsyncEra.sol";
import {IStateTransitionManager} from "../../src/interfaces/IStateTransitionManager.sol";
import {IPausable} from "../../src/interfaces/IPausable.sol";

import {ProtocolUpgradeHandler} from "../../src/ProtocolUpgradeHandler.sol";

// This test is focused to ensure that the new Proxy-based setup works correctly
contract MainnetRedeployForkTest is Test {
    using stdStorage for StdStorage;


}
