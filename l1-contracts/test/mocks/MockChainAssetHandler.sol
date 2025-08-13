// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IChainAssetHandler} from "../../src/interfaces/IChainAssetHandler.sol";

contract MockChainAssetHandler is IChainAssetHandler {
    function pauseMigration() external override {}
    function unpauseMigration() external override {}
}
