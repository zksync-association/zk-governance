// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians} from "./RemoveGuardians.s.sol";

/// @title StageRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on the stage
/// environment. See MainnetRemoveGuardians for details.
///
/// Usage:
///   [CREATE2_SALT=<bytes32>] [DEPLOY_OUTPUT_TOML=<path>] \
///     forge script scripts/StageRemoveGuardians.s.sol:StageRemoveGuardians \
///     --rpc-url <L1_STAGE_RPC> --broadcast --verify --etherscan-api-key <KEY> \
///     <--private-key|--ledger|--account> ... -vvvv
contract StageRemoveGuardians is RemoveGuardians {
    // ProtocolUpgradeHandler on stage (testnet)
    // (verified via stage Bridgehub.owner() at 0x236D1c3Ff32Bd0Ca26b72Af287E895627c0478cE)
    address constant PROTOCOL_UPGRADE_HANDLER = 0x8f08627524aeD610192132A425D6b9C32a1727EF;

    function run() external {
        console2.log("=== Stage Guardians Removal ===");

        // Stage runs the TestnetProtocolUpgradeHandler, like v31 does.
        runRemoveGuardians(PROTOCOL_UPGRADE_HANDLER, true);
    }
}
