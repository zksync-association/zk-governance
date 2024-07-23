// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2 as console} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ISafeSetup.sol";
import "./IGnosisSafeProxyFactory.sol";
import "./ICREATE3Factory.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/TestnetProtocolUpgradeHandler.sol";
import "../src/EmergencyUpgradeBoard.sol";

contract TestnetDeploy is Script {
    ICREATE3Factory constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    IGnosisSafeProxyFactory constant SAFE_PROXY_FACTORY = IGnosisSafeProxyFactory(0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC);
    address constant SAFE_SINGLETON = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    address constant COMPATIBILITY_FALLBACK_HANDLER = 0x017062a1dE2FE6b99BE3d9d37841FeD19F573804;

    bytes32 PROTOCOL_UPGRADE_HANDLER_SALT = keccak256("TestnetProtocolUpgradeHandler");
    bytes32 GUARDIANS_SALT = keccak256("Guardians");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard");

    IZKsyncEra constant ZKSYNC_ERA = IZKsyncEra(0x6d6e010A2680E2E5a3b097ce411528b36d880EF6);
    IStateTransitionManager constant STATE_TRANSITION_MANAGER = IStateTransitionManager(0x8b448ac7cd0f18F3d8464E2645575772a26A3b6b);
    IPausable constant BRIDGE_HUB = IPausable(0x236D1c3Ff32Bd0Ca26b72Af287E895627c0478cE);
    IPausable constant SHARED_BRIDGE = IPausable(0x6F03861D12E6401623854E494beACd66BC46e6F0);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        address[] memory guardiansMembers = new address[](8);
        for(uint256 i=0;i<8;i++) {
            address[] memory owners = new address[](1);
            owners[0] = vm.envAddress("GURDIAN_OWNER");
            bytes memory initializer = abi.encodeCall(ISafeSetup.setup, (owners, 1, address(0), "", COMPATIBILITY_FALLBACK_HANDLER, address(0), 0, payable(address(0))));
            address safe = SAFE_PROXY_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, i);
            guardiansMembers[i] = safe;
        }
        guardiansMembers = Utils.sortAddresses(guardiansMembers);

        address[] memory securityCouncilMembers = new address[](12);
        for(uint256 i=0;i<12;i++) {
            address[] memory owners = new address[](1);
            owners[0] = vm.envAddress("SECURITY_COUNCIL_OWNER");
            bytes memory initializer = abi.encodeCall(ISafeSetup.setup, (owners, 1, address(0), "", COMPATIBILITY_FALLBACK_HANDLER, address(0), 0, payable(address(0))));
            address safe = SAFE_PROXY_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, i+12);
            securityCouncilMembers[i] = safe;
        }
        securityCouncilMembers = Utils.sortAddresses(securityCouncilMembers);
        
        address zkFoundation;
        {
            address[] memory owners = new address[](1);
            owners[0] = vm.envAddress("ZK_FOUNDATION_OWNER");
            bytes memory initializer = abi.encodeCall(ISafeSetup.setup, (owners, 1, address(0), "", COMPATIBILITY_FALLBACK_HANDLER, address(0), 0, payable(address(0))));
            zkFoundation = SAFE_PROXY_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, 21);
        }

        vm.stopBroadcast();

        address protocolUpgradeHandler = CREATE3_FACTORY.getDeployed(deployerWallet.addr, PROTOCOL_UPGRADE_HANDLER_SALT);
        console.log("Protocol Upgrade Handler address: ", protocolUpgradeHandler);
        address guardians = CREATE3_FACTORY.getDeployed(deployerWallet.addr, GUARDIANS_SALT);
        console.log("Guardians address: ", guardians);
        address securityCouncil = CREATE3_FACTORY.getDeployed(deployerWallet.addr, SECURITY_COUNCIL_SALT);
        console.log("Security Council address: ", securityCouncil);
        address emergencyUpgradeBoard = CREATE3_FACTORY.getDeployed(deployerWallet.addr, EMERGENCY_UPGRADE_BOARD_SALT);
        console.log("Emergency Upgrade Board address: ", emergencyUpgradeBoard);

        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");
        bytes memory protocolUpgradeHandlerConstructorArgs = abi.encode(securityCouncil, guardians, emergencyUpgradeBoard, l2ProtocolGovernor, ZKSYNC_ERA, STATE_TRANSITION_MANAGER, BRIDGE_HUB, SHARED_BRIDGE);
        bytes memory protocolUpgradeHandlerCreationCode = abi.encodePacked(type(TestnetProtocolUpgradeHandler).creationCode, protocolUpgradeHandlerConstructorArgs);

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
}
