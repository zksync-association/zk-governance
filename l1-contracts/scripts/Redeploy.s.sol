// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ISafeSetup.sol";
import "./IGnosisSafeProxyFactory.sol";
import "./ICREATE3Factory.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/EmergencyUpgradeBoard.sol";
import "../src/Multisig.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol"; 
import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol"; 

import {IStateTransitionManager} from "../src/interfaces/IStateTransitionManager.sol";
import {IL1SharedBridge} from "../src/interfaces/IL1SharedBridge.sol";

struct DeployedContracts {
    address protocolUpgradeHandlerImpl;
    address protocolUpgradeHandlerProxy;
    address guardians;
    address securityCouncil;
    address emergencyUpgradeBoard;
}

// A common redeploy script that can be used for both mainnet and testnet scripts
contract Redeploy is Script {
    ICREATE3Factory constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    bytes32 PROTOCOL_UPGRADE_HANDLER_PROXY_SALT = keccak256("ProtocolUpgradeHandlerProxy3"); 
    bytes32 PROTOCOL_UPGRADE_HANDLER_IMPL_SALT = keccak256("ProtocolUpgradeHandlerImpl3");
    bytes32 GUARDIANS_SALT = keccak256("Guardians3");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil3");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard3");

    struct CurrentSystemParams {
        address[] securityCouncilMembers;
        address[] guardiansMembers;
        address zkFoundationSafe;
        address zksyncEra;
        address stateTransitionManager;
        address bridgehub;
        address sharedBridge;
        address validatorTimelock;
        address l1Erc20Bridge;
    }

    // Holds the addresses that were deployed. It is only needed for testing purposes for 
    // making the fork-testing easier.
    DeployedContracts internal deployedAddresses;

    function getDeployedAddresses() public view returns (DeployedContracts memory contracts) {
        contracts = deployedAddresses;
    }

    function readMembers(address _multisig) internal view returns (address[] memory members) {
        uint256 totalMembers = uint256(vm.load(_multisig, 0));
        members = new address[](totalMembers);

        for(uint256  i = 0; i < totalMembers; i++) {
            members[i] = Multisig(_multisig).members(i);
            require(members[i] != address(0), "Can not have empty members");
        }

        try Multisig(_multisig).members(totalMembers) returns (address addr) {
            revert("Wrong number of members");
        }
        catch {
            // It is expected to revert since the number of members is incorrect
        }
    }

    // To reduce a chance for error, we just copy as much data as possible from the existing protocol upgrade handler.
    function extractDataFromProtocolUpgradeHandler(ProtocolUpgradeHandler _currentProtocolUpgradeHandler) internal view returns (CurrentSystemParams memory) {
        address securityCouncil = _currentProtocolUpgradeHandler.securityCouncil();
        address guardians = _currentProtocolUpgradeHandler.guardians();
        EmergencyUpgradeBoard emergencyUpgradeBoard = EmergencyUpgradeBoard(_currentProtocolUpgradeHandler.emergencyUpgradeBoard());

        address zksyncEra = address(_currentProtocolUpgradeHandler.ZKSYNC_ERA());
        address stateTransitionManager = address(_currentProtocolUpgradeHandler.STATE_TRANSITION_MANAGER());
        address bridgehub = address(_currentProtocolUpgradeHandler.BRIDGE_HUB());
        address sharedBridge = address(_currentProtocolUpgradeHandler.SHARED_BRIDGE());

        address validatorTimelock = IStateTransitionManager(stateTransitionManager).validatorTimelock();
        address l1Erc20Bridge = IL1SharedBridge(sharedBridge).legacyBridge();

        // A small cross check for consistency
        require(emergencyUpgradeBoard.SECURITY_COUNCIL() == securityCouncil, "incorrect security council");
        require(emergencyUpgradeBoard.GUARDIANS() == guardians, "incorrect guardians");
        require(emergencyUpgradeBoard.PROTOCOL_UPGRADE_HANDLER() == IProtocolUpgradeHandler(address(_currentProtocolUpgradeHandler)), "incorrect protocol upgrade handler");

        return CurrentSystemParams({
            securityCouncilMembers: readMembers(securityCouncil),
            guardiansMembers: readMembers(guardians),
            zkFoundationSafe: emergencyUpgradeBoard.ZK_FOUNDATION_SAFE(),
            zksyncEra: zksyncEra,
            stateTransitionManager: stateTransitionManager,
            bridgehub: bridgehub,
            sharedBridge: sharedBridge,
            validatorTimelock: validatorTimelock,
            l1Erc20Bridge: l1Erc20Bridge
        });
    }

    function runRedeploy(
        address _currentHandler,
        bool _useTestnetUpgradeHandler
    ) public {
        // To ensure that all the data is the same as before, we fetch what it is now
        // and then we will use it to deploy our contracts.
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(_currentHandler));
        CurrentSystemParams memory info = extractDataFromProtocolUpgradeHandler(currentHandler);
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        DeployedContracts memory addresses = predictAddresses(deployerWallet.addr);

        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");

        // Firstly, we deploy the implementation
        {
            bytes memory protocolUpgradeHandlerConstructorArgs = abi.encode(l2ProtocolGovernor, info.zksyncEra, info.stateTransitionManager, info.bridgehub, info.sharedBridge);
            bytes memory protocolUpgradeHandlerBytecode;
            if (_useTestnetUpgradeHandler) {
                protocolUpgradeHandlerBytecode = type(TestnetProtocolUpgradeHandler).creationCode;
            } else {
                protocolUpgradeHandlerBytecode = type(ProtocolUpgradeHandler).creationCode;
            }
            console2.log("ProtocolUpgradeHandler impl constructor params: ");
            console2.logBytes(protocolUpgradeHandlerConstructorArgs);
            bytes memory protocolUpgradeHandlerCreationCode = abi.encodePacked(protocolUpgradeHandlerBytecode, protocolUpgradeHandlerConstructorArgs);
            vm.startBroadcast(deployerWallet.addr);
            CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_IMPL_SALT, protocolUpgradeHandlerCreationCode);
            vm.stopBroadcast();
        }

        // Now, we can deploy the proxy.
        {
            // Note, that the proxy is itself the owner. The calls to the proxy impl will still be allowed, since
            // the TransparentUpgradeableProxy automatically creates a ProxyAdmin instance. 
            bytes memory initdata = abi.encodeCall(ProtocolUpgradeHandler.initialize, (addresses.securityCouncil, addresses.guardians, addresses.emergencyUpgradeBoard));
            bytes memory proxyConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerImpl, addresses.protocolUpgradeHandlerProxy, initdata);
            console2.log("ProtocolUpgradeHandler proxy constructor params: ");
            console2.logBytes(proxyConstructorArgs);

            bytes memory proxyCreationCode = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, proxyConstructorArgs);
            vm.startBroadcast(deployerWallet.addr);
            CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_PROXY_SALT, proxyCreationCode);
            vm.stopBroadcast();
        }
        
        // Deploying guardians
        {
            bytes memory guardiansConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, info.zksyncEra, info.guardiansMembers);
            console2.log("Guardians constructor params: ");
            console2.logBytes(guardiansConstructorArgs);

            bytes memory guardiansCreationCode = abi.encodePacked(type(Guardians).creationCode, guardiansConstructorArgs);   
            vm.startBroadcast(deployerWallet.addr);
            CREATE3_FACTORY.deploy(GUARDIANS_SALT, guardiansCreationCode);
            vm.stopBroadcast();
        }

        // Deploying security council
        {
            bytes memory securityCouncilConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, info.securityCouncilMembers);
            console2.log("Security council constructor params: ");
            console2.logBytes(securityCouncilConstructorArgs);

            bytes memory securityCouncilCreationCode = abi.encodePacked(type(SecurityCouncil).creationCode, securityCouncilConstructorArgs);
            vm.startBroadcast(deployerWallet.addr);
            CREATE3_FACTORY.deploy(SECURITY_COUNCIL_SALT, securityCouncilCreationCode);
            vm.stopBroadcast();   
        }

        // Deploying emergency upgrade board
        {
            bytes memory emergencyUpgradeBoardConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, addresses.securityCouncil, addresses.guardians, info.zkFoundationSafe);
            console2.log("Emergency upgrde board constructor params: ");
            console2.logBytes(emergencyUpgradeBoardConstructorArgs);

            bytes memory emergencyUpgradeBoardCreationCode = abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, emergencyUpgradeBoardConstructorArgs);
            vm.startBroadcast(deployerWallet.addr);
            CREATE3_FACTORY.deploy(EMERGENCY_UPGRADE_BOARD_SALT, emergencyUpgradeBoardCreationCode);
            vm.stopBroadcast();
        }

        // We store it inside the script for testing purposes.
        deployedAddresses = addresses;
    }

    function predictAddresses(address deployerWallet) public returns(DeployedContracts memory deployedContracts) {
        deployedContracts.protocolUpgradeHandlerImpl = CREATE3_FACTORY.getDeployed(deployerWallet, PROTOCOL_UPGRADE_HANDLER_IMPL_SALT);
        console2.log("Protocol Upgrade Handler impl address: ", deployedContracts.protocolUpgradeHandlerImpl);
        deployedContracts.protocolUpgradeHandlerProxy = CREATE3_FACTORY.getDeployed(deployerWallet, PROTOCOL_UPGRADE_HANDLER_PROXY_SALT);
        console2.log("Protocol Upgrade Handler proxy address: ", deployedContracts.protocolUpgradeHandlerProxy);
        deployedContracts.guardians = CREATE3_FACTORY.getDeployed(deployerWallet, GUARDIANS_SALT);
        console2.log("Guardians address: ", deployedContracts.guardians);
        deployedContracts.securityCouncil = CREATE3_FACTORY.getDeployed(deployerWallet, SECURITY_COUNCIL_SALT);
        console2.log("Security Council address: ", deployedContracts.securityCouncil);
        deployedContracts.emergencyUpgradeBoard = CREATE3_FACTORY.getDeployed(deployerWallet, EMERGENCY_UPGRADE_BOARD_SALT);
        console2.log("Emergency Upgrade Board address: ", deployedContracts.emergencyUpgradeBoard);
    }
}
