// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RedeploySecurityCouncil} from "./RedeploySecurityCouncil.s.sol";
import {Multisig} from "../src/Multisig.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";

/// @title StageRedeploySecurityCouncil
/// @notice Redeploys the SecurityCouncil and EmergencyUpgradeBoard on stage environment.
/// Queries the first 8 members from the existing SecurityCouncil (on stage they all
/// use the underlying private keys so it is fine).
///
/// Usage:
///   PRIVATE_KEY=<deployer_pk> forge script scripts/StageRedeploySecurityCouncil.s.sol:StageRedeploySecurityCouncil \
///     --rpc-url <L1_STAGE_RPC> --broadcast --verify --etherscan-api-key <KEY> -vvvv
contract StageRedeploySecurityCouncil is RedeploySecurityCouncil {
    // Current ProtocolUpgradeHandler on stage (testnet)
    // (verified via stage Bridgehub.owner() at 0x236D1c3Ff32Bd0Ca26b72Af287E895627c0478cE)
    address constant CURRENT_PROTOCOL_UPGRADE_HANDLER = 0x8f08627524aeD610192132A425D6b9C32a1727EF;

    function run() external {
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(CURRENT_PROTOCOL_UPGRADE_HANDLER));
        address currentSecurityCouncil = currentHandler.securityCouncil();

        console2.log("=== Stage SecurityCouncil Redeployment ===");
        console2.log("Querying first 8 members from existing SecurityCouncil:", currentSecurityCouncil);

        // Read the first 8 members from the existing SecurityCouncil
        address[] memory newMembers = new address[](8);
        for (uint256 i = 0; i < 8; i++) {
            newMembers[i] = Multisig(currentSecurityCouncil).members(i);
            console2.log("Member", i, newMembers[i]);
        }

        runRedeploySecurityCouncil(
            CURRENT_PROTOCOL_UPGRADE_HANDLER,
            newMembers,
            false // no membership verification needed on stage
        );
    }
}
