// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ICREATE3Factory.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/ProtocolUpgradeHandlerT.sol";
import "../src/EmergencyUpgradeBoard.sol";

contract MainnetDeploy is Script {
    ICREATE3Factory constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    bytes32 PROTOCOL_UPGRADE_HANDLER_SALT = keccak256("ProtocolUpgradeHandler");
    bytes32 GUARDIANS_SALT = keccak256("Guardians");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard");

    IZKsyncEra constant ZKSYNC_ERA = IZKsyncEra(0x32400084C286CF3E17e7B677ea9583e60a000324);
    IStateTransitionManager constant STATE_TRANSITION_MANAGER = IStateTransitionManager(0xc2eE6b6af7d616f6e27ce7F4A451Aedc2b0F5f5C);
    IPausable constant BRIDGE_HUB = IPausable(0x303a465B659cBB0ab36eE643eA362c509EEb5213);
    IPausable constant SHARED_BRIDGE = IPausable(0xD7f9f54194C633F36CCD5F3da84ad4a1c38cB2cB);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        address[] memory guardiansMembers = vm.envAddress("GURDIAN_MEMBERS", ",");
        guardiansMembers = Utils.sortAddresses(guardiansMembers);

        address[] memory securityCouncilMembers = vm.envAddress("SECURITY_COUNCIL_MEMBERS", ",");
        securityCouncilMembers = Utils.sortAddresses(securityCouncilMembers);
        
        address zkFoundation = vm.envAddress("ZK_FOUNDATION");

        (address protocolUpgradeHandler, address guardians, address securityCouncil, address emergencyUpgradeBoard) = predictAddresses(deployerWallet.addr);

        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");
        bytes memory protocolUpgradeHandlerConstructorArgs = abi.encode(securityCouncil, guardians, emergencyUpgradeBoard, l2ProtocolGovernor, ZKSYNC_ERA, STATE_TRANSITION_MANAGER, BRIDGE_HUB, SHARED_BRIDGE);
        bytes memory protocolUpgradeHandlerCreationCode = abi.encodePacked(type(ProtocolUpgradeHandler).creationCode, protocolUpgradeHandlerConstructorArgs);

        vm.startBroadcast();
        CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_SALT, protocolUpgradeHandlerCreationCode);
        vm.stopBroadcast();

        bytes memory guardiansConstructorArgs = abi.encode(protocolUpgradeHandler, ZKSYNC_ERA, guardiansMembers);
        bytes memory guardiansCreationCode = abi.encodePacked(type(Guardians).creationCode, guardiansConstructorArgs);
        
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(GUARDIANS_SALT, guardiansCreationCode);
        vm.stopBroadcast();

        bytes memory securityCouncilConstructorArgs = abi.encode(protocolUpgradeHandler, securityCouncilMembers);
        bytes memory securityCouncilCreationCode = abi.encodePacked(type(SecurityCouncil).creationCode, securityCouncilConstructorArgs);
        
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(SECURITY_COUNCIL_SALT, securityCouncilCreationCode);
        vm.stopBroadcast();
        
        bytes memory emergencyUpgradeBoardConstructorArgs = abi.encode(protocolUpgradeHandler, securityCouncil, guardians, zkFoundation);
        bytes memory emergencyUpgradeBoardCreationCode = abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, emergencyUpgradeBoardConstructorArgs);
        
        vm.startBroadcast();
        CREATE3_FACTORY.deploy(EMERGENCY_UPGRADE_BOARD_SALT, emergencyUpgradeBoardCreationCode);
        vm.stopBroadcast();
    }

    function predictAddresses(address deployerWallet) public returns(address protocolUpgradeHandler, address guardians, address securityCouncil, address emergencyUpgradeBoard) {
        protocolUpgradeHandler = CREATE3_FACTORY.getDeployed(deployerWallet, PROTOCOL_UPGRADE_HANDLER_SALT);
        console2.log("Protocol Upgrade Handler address: ", protocolUpgradeHandler);
        guardians = CREATE3_FACTORY.getDeployed(deployerWallet, GUARDIANS_SALT);
        console2.log("Guardians address: ", guardians);
        securityCouncil = CREATE3_FACTORY.getDeployed(deployerWallet, SECURITY_COUNCIL_SALT);
        console2.log("Security Council address: ", securityCouncil);
        emergencyUpgradeBoard = CREATE3_FACTORY.getDeployed(deployerWallet, EMERGENCY_UPGRADE_BOARD_SALT);
        console2.log("Emergency Upgrade Board address: ", emergencyUpgradeBoard);
    }
}
