// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians} from "./RemoveGuardians.s.sol";

/// @title MainnetRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on mainnet: deploys the
/// new ProtocolUpgradeHandler implementation (ZK Foundation instead of Guardians) and the new
/// two-party EmergencyUpgradeBoard (Security Council + ZK Foundation), and generates the protocol
/// upgrade Call[] that installs them and hands the ZK Foundation role to the ZK Foundation Safe.
///
/// Everything except the handler address is read from the handler, so the script runs once the
/// v31 upgrade (ZIP-18) is executed. Before that, RemoveGuardiansForkTest replays v31 on a fork
/// and runs the script against the result.
///
/// Usage:
///   [CREATE2_SALT=<bytes32>] [DEPLOY_OUTPUT_TOML=<path>] \
///     forge script scripts/MainnetRemoveGuardians.s.sol:MainnetRemoveGuardians \
///     --rpc-url <L1_MAINNET_RPC> --broadcast --verify --etherscan-api-key <KEY> \
///     <--private-key|--ledger|--account> ... -vvvv
contract MainnetRemoveGuardians is RemoveGuardians {
    // ProtocolUpgradeHandler proxy on mainnet
    // (verified via Bridgehub.owner() at 0x303a465B659cBB0ab36eE643eA362c509EEb5213)
    address constant PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;

    function run() external {
        console2.log("=== Mainnet Guardians Removal ===");

        runRemoveGuardians(PROTOCOL_UPGRADE_HANDLER, false);
    }
}
