// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {RedeploySecurityCouncil} from "./RedeploySecurityCouncil.s.sol";

/// @title MainnetRedeploySecurityCouncil
/// @notice Redeploys the SecurityCouncil and EmergencyUpgradeBoard on L1 mainnet
/// with the 8 retained ZKSC members. Verifies all new members were part of the
/// previous SecurityCouncil.
///
/// Usage:
///   PRIVATE_KEY=<deployer_pk> forge script scripts/MainnetRedeploySecurityCouncil.s.sol:MainnetRedeploySecurityCouncil \
///     --rpc-url <L1_MAINNET_RPC> --broadcast --verify --etherscan-api-key <KEY> -vvvv
contract MainnetRedeploySecurityCouncil is RedeploySecurityCouncil {
    // Current ProtocolUpgradeHandler proxy on mainnet
    // (verified via Bridgehub.owner() at 0x303a465B659cBB0ab36eE643eA362c509EEb5213)
    address constant CURRENT_PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;

    function run() external {
        // The 8 retained ZKSC members
        address[] memory newMembers = new address[](8);
        newMembers[0] = 0x84BF0Ac41Eeb74373Ddddae8b7055Bf2bD3CE6E0; // Chainlight
        newMembers[1] = 0x35eA56fd9eAd2567F339Eb9564B6940b9DD5653F; // Cyfrin
        newMembers[2] = 0xB7aC3A79A23B148c85fba259712c5A1e7ad0ca44; // Dedaub
        newMembers[3] = 0xc3Abc9f9AA75Be8341E831482cdA0125a7B1A23e; // Matter Labs
        newMembers[4] = 0x69462a81ba94D64c404575f1899a464F123497A2; // Nethermind
        newMembers[5] = 0x34Ea62D4b9bBB8AD927eFB6ab31E3Ab3474aC93a; // Open Zeppelin
        newMembers[6] = 0xFB90Da9DC45378A1B50775Beb03aD10C7E8DC231; // Peckshield
        newMembers[7] = 0x9B8Be3278B7F0168D82059eb6BAc5991DcdfA803; // Spearbit

        console2.log("=== Mainnet SecurityCouncil Redeployment ===");
        console2.log("Verifying all new members are in the existing SecurityCouncil...");

        runRedeploySecurityCouncil(
            CURRENT_PROTOCOL_UPGRADE_HANDLER,
            newMembers,
            true // verify membership against old SC
        );
    }
}
