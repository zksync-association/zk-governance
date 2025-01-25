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

// A common redeploy script that can be used for both mainnet and testnet scripts
contract Redeploy is Script {
    ICREATE3Factory constant CREATE3_FACTORY = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    bytes32 PROTOCOL_UPGRADE_HANDLER_PROXY_SALT = keccak256("ProtocolUpgradeHandlerProxy"); 
    bytes32 PROTOCOL_UPGRADE_HANDLER_IMPL_SALT = keccak256("ProtocolUpgradeHandlerImpl");
    bytes32 GUARDIANS_SALT = keccak256("Guardians");
    bytes32 SECURITY_COUNCIL_SALT = keccak256("SecurityCouncil");
    bytes32 EMERGENCY_UPGRADE_BOARD_SALT = keccak256("EmergencyUpgradeBoard");

    struct CurrentSystemParams {
        address[] securityCouncilMembers;
        address[] guardiansMembers;
        address zkFoundationSafe;
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

    function extractDataFromProtocolUpgradeHandler(ProtocolUpgradeHandler _currentProtocolUpgradeHandler) internal view returns (CurrentSystemParams memory) {
        address securityCouncil = _currentProtocolUpgradeHandler.securityCouncil();
        address guardians = _currentProtocolUpgradeHandler.guardians();
        EmergencyUpgradeBoard emergencyUpgradeBoard = EmergencyUpgradeBoard(_currentProtocolUpgradeHandler.emergencyUpgradeBoard());

        // A small cross check for consistency
        require(emergencyUpgradeBoard.SECURITY_COUNCIL() == securityCouncil, "incorrect security council");
        require(emergencyUpgradeBoard.GUARDIANS() == guardians, "incorrect guardians");
        require(emergencyUpgradeBoard.PROTOCOL_UPGRADE_HANDLER() == IProtocolUpgradeHandler(address(_currentProtocolUpgradeHandler)), "incorrect protocol upgrade handler");

        return CurrentSystemParams({
            securityCouncilMembers: readMembers(securityCouncil),
            guardiansMembers: readMembers(guardians),
            zkFoundationSafe: emergencyUpgradeBoard.ZK_FOUNDATION_SAFE()
        });
    }

    function runRedeploy(
        address _currentHandler,
        address _zkSyncEra,
        address _stateTransitionManagerAddr,
        address _bridgehub,
        address _sharedBridge,
        bytes memory _protocolUpgradeHandlerBytecode
    ) public {
        // To ensure that all the data is the same as before, we fetch what it is now
        // and then we will use it to deploy our contracts.
        CurrentSystemParams memory info = extractDataFromProtocolUpgradeHandler(ProtocolUpgradeHandler(payable(_currentHandler)));
        
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        Vm.Wallet memory deployerWallet = vm.createWallet(deployerPrivateKey);

        DeployedContracts memory addresses = predictAddresses(deployerWallet.addr);

        address l2ProtocolGovernor = vm.envAddress("L2_PROTOCOL_GOVERNOR");

        // Firstly, we deploy the implementation
        {
            bytes memory protocolUpgradeHandlerConstructorArgs = abi.encode(addresses.securityCouncil, addresses.guardians, addresses.emergencyUpgradeBoard, l2ProtocolGovernor, _zkSyncEra, _stateTransitionManagerAddr, _bridgehub, _sharedBridge);
            bytes memory protocolUpgradeHandlerCreationCode = abi.encodePacked(_protocolUpgradeHandlerBytecode, protocolUpgradeHandlerConstructorArgs);
            vm.startBroadcast();
            CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_IMPL_SALT, protocolUpgradeHandlerCreationCode);
            vm.stopBroadcast();
        }

        // Now, we can deploy the proxy.
        {
            // Note, that the proxy is itself the owner. The calls to the proxy impl will still be allowed, since
            // the TransparentUpgradeableProxy automatically creates a ProxyAdmin instance. 
            bytes memory initdata = abi.encodeCall(ProtocolUpgradeHandler.initialize, (addresses.securityCouncil, addresses.guardians, addresses.emergencyUpgradeBoard));
            bytes memory proxyConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerImpl, addresses.protocolUpgradeHandlerProxy, initdata);
            bytes memory proxyCreationCode = abi.encodePacked(type(TransparentUpgradeableProxy).creationCode, proxyConstructorArgs);

            vm.startBroadcast();
            CREATE3_FACTORY.deploy(PROTOCOL_UPGRADE_HANDLER_PROXY_SALT, proxyCreationCode);
            vm.stopBroadcast();
        }
        
        // Deploying guardians
        {
            bytes memory guardiansConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, _zkSyncEra, info.guardiansMembers);
            bytes memory guardiansCreationCode = abi.encodePacked(type(Guardians).creationCode, guardiansConstructorArgs);   
            vm.startBroadcast();
            CREATE3_FACTORY.deploy(GUARDIANS_SALT, guardiansCreationCode);
            vm.stopBroadcast();
        }

        // Deploying security council
        {
            bytes memory securityCouncilConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, info.securityCouncilMembers);
            bytes memory securityCouncilCreationCode = abi.encodePacked(type(SecurityCouncil).creationCode, securityCouncilConstructorArgs);
            
            vm.startBroadcast();
            CREATE3_FACTORY.deploy(SECURITY_COUNCIL_SALT, securityCouncilCreationCode);
            vm.stopBroadcast();   
        }

        // Deploying emergency upgrade board
        {
            bytes memory emergencyUpgradeBoardConstructorArgs = abi.encode(addresses.protocolUpgradeHandlerProxy, addresses.securityCouncil, addresses.guardians, info.zkFoundationSafe);
            bytes memory emergencyUpgradeBoardCreationCode = abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, emergencyUpgradeBoardConstructorArgs);
            
            vm.startBroadcast();
            CREATE3_FACTORY.deploy(EMERGENCY_UPGRADE_BOARD_SALT, emergencyUpgradeBoardCreationCode);
            vm.stopBroadcast();
        }
    }

    struct DeployedContracts {
        address protocolUpgradeHandlerImpl;
        address protocolUpgradeHandlerProxy;
        address guardians;
        address securityCouncil;
        address emergencyUpgradeBoard;
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
