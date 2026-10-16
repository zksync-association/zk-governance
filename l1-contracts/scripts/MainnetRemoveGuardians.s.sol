// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians, RemoveGuardiansParams} from "./RemoveGuardians.s.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";

/// @title MainnetRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on mainnet:
/// deploys the new two-party EmergencyUpgradeBoard (Security Council + ZK Foundation)
/// and generates the protocol upgrade Call[] that hands the guardians role on the
/// ProtocolUpgradeHandler over to the ZK Foundation Safe.
///
/// The Call[] is built against the governance set installed by the v31 upgrade (ZIP-18,
/// stage 0 `initialize` of the ProtocolUpgradeHandler) and reverts until it is in place,
/// so the removal can be proposed before v31 is executed but only executed after it.
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

    // Governance set installed by v31, see `[zk_governance]` in era-contracts
    // l1-contracts/upgrade-envs/v0.31.0-interopB/output/mainnet/ecosystem.toml and the
    // stage 0 `upgradeAndCall(..., initialize(...))` call in transaction-simulator
    // decoded-calldata/2026-09-08-v31-interopB-mainnet.json.
    address constant V31_SECURITY_COUNCIL = 0x29D2e773A31C07D375c50F0110422832bd044d08;
    address constant V31_GUARDIANS = 0x8f525e55F76050d8dFdDa4870DA1b3ede54E908F;
    address constant V31_EMERGENCY_UPGRADE_BOARD = 0x91989F9BB8391D3471D2672Ec001921cB14C4b7C;

    function run() external {
        // The guardians role goes to the same ZK Foundation Safe that co-signs emergency upgrades.
        address zkFoundationSafe = EmergencyUpgradeBoard(V31_EMERGENCY_UPGRADE_BOARD).ZK_FOUNDATION_SAFE();

        console2.log("=== Mainnet Guardians Removal ===");

        runRemoveGuardians(
            RemoveGuardiansParams({
                protocolUpgradeHandler: PROTOCOL_UPGRADE_HANDLER,
                expectedSecurityCouncil: V31_SECURITY_COUNCIL,
                expectedGuardians: V31_GUARDIANS,
                expectedEmergencyUpgradeBoard: V31_EMERGENCY_UPGRADE_BOARD,
                newGuardians: zkFoundationSafe
            })
        );
    }
}
