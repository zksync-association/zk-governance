// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RemoveGuardians, RemoveGuardiansParams} from "./RemoveGuardians.s.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";

/// @title StageRemoveGuardians
/// @notice Removes the Guardians from the L1 side of ZKsync governance on the stage
/// environment. See MainnetRemoveGuardians for details.
///
/// Usage:
///   [NEW_GUARDIANS=<foundation_multisig>] [CREATE2_SALT=<bytes32>] [DEPLOY_OUTPUT_TOML=<path>] \
///     forge script scripts/StageRemoveGuardians.s.sol:StageRemoveGuardians \
///     --rpc-url <L1_STAGE_RPC> --broadcast --verify --etherscan-api-key <KEY> \
///     <--private-key|--ledger|--account> ... -vvvv
contract StageRemoveGuardians is RemoveGuardians {
    // ProtocolUpgradeHandler on stage (testnet)
    // (verified via stage Bridgehub.owner() at 0x236D1c3Ff32Bd0Ca26b72Af287E895627c0478cE)
    address constant PROTOCOL_UPGRADE_HANDLER = 0x8f08627524aeD610192132A425D6b9C32a1727EF;

    // Governance set installed by v31 on stage, see `[zk_governance]` in era-contracts
    // l1-contracts/upgrade-envs/v0.31.0-interopB/output/stage/ecosystem.toml.
    address constant V31_SECURITY_COUNCIL = 0x1D3D9afB89b51b3f0b4958cA55729c83247C57dB;
    address constant V31_GUARDIANS = 0x6C9499D438cB708457235450aa7dff858cA1585c;
    address constant V31_EMERGENCY_UPGRADE_BOARD = 0x24de9c60f6E7226F996D4837Feb9337C207B07e6;

    function run() external {
        address zkFoundationSafe = EmergencyUpgradeBoard(V31_EMERGENCY_UPGRADE_BOARD).ZK_FOUNDATION_SAFE();
        address newGuardians = vm.envOr("NEW_GUARDIANS", zkFoundationSafe);

        console2.log("=== Stage Guardians Removal ===");

        runRemoveGuardians(
            RemoveGuardiansParams({
                protocolUpgradeHandler: PROTOCOL_UPGRADE_HANDLER,
                expectedSecurityCouncil: V31_SECURITY_COUNCIL,
                expectedGuardians: V31_GUARDIANS,
                expectedEmergencyUpgradeBoard: V31_EMERGENCY_UPGRADE_BOARD,
                newGuardians: newGuardians
            })
        );
    }
}
