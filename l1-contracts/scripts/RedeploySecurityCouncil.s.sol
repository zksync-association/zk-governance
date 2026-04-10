// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/EmergencyUpgradeBoard.sol";
import "../src/Multisig.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

struct SCRedeployedContracts {
    address securityCouncil;
    address emergencyUpgradeBoard;
}

/// @title RedeploySecurityCouncil
/// @notice Base script for redeploying the SecurityCouncil (8 members, 6/8 thresholds)
/// and EmergencyUpgradeBoard, then generating the Call[] for the ProtocolUpgradeHandler
/// to update its references.
contract RedeploySecurityCouncil is Script {
    SCRedeployedContracts internal deployedAddresses;

    function getDeployedAddresses() public view returns (SCRedeployedContracts memory) {
        return deployedAddresses;
    }

    function readMembers(address _multisig) internal view returns (address[] memory members) {
        uint256 totalMembers = uint256(vm.load(_multisig, 0));
        members = new address[](totalMembers);

        for (uint256 i = 0; i < totalMembers; i++) {
            members[i] = Multisig(_multisig).members(i);
            require(members[i] != address(0), "Can not have empty members");
        }

        try Multisig(_multisig).members(totalMembers) returns (address) {
            revert("Wrong number of members");
        } catch {
            // Expected revert
        }
    }

    /// @notice Main redeploy function.
    /// @param _currentHandler Address of the current ProtocolUpgradeHandler (proxy).
    /// @param _newMembers Array of 8 new SecurityCouncil member addresses.
    /// @param _verifyMembership If true, checks that every new member was a member of the old SecurityCouncil.
    function runRedeploySecurityCouncil(
        address _currentHandler,
        address[] memory _newMembers,
        bool _verifyMembership
    ) internal {
        ProtocolUpgradeHandler currentHandler = ProtocolUpgradeHandler(payable(_currentHandler));

        address currentSecurityCouncil = currentHandler.securityCouncil();
        address currentGuardians = currentHandler.guardians();
        address currentEmergencyUpgradeBoard = currentHandler.emergencyUpgradeBoard();
        EmergencyUpgradeBoard eub = EmergencyUpgradeBoard(currentEmergencyUpgradeBoard);
        address zkFoundationSafe = eub.ZK_FOUNDATION_SAFE();

        console2.log("=== Current System State ===");
        console2.log("ProtocolUpgradeHandler:", _currentHandler);
        console2.log("Current SecurityCouncil:", currentSecurityCouncil);
        console2.log("Current Guardians:", currentGuardians);
        console2.log("Current EmergencyUpgradeBoard:", currentEmergencyUpgradeBoard);
        console2.log("ZK Foundation Safe:", zkFoundationSafe);

        // Verify membership if required (mainnet)
        if (_verifyMembership) {
            address[] memory oldMembers = readMembers(currentSecurityCouncil);
            console2.log("Old SecurityCouncil member count:", oldMembers.length);
            for (uint256 i = 0; i < _newMembers.length; i++) {
                bool found = false;
                for (uint256 j = 0; j < oldMembers.length; j++) {
                    if (_newMembers[i] == oldMembers[j]) {
                        found = true;
                        break;
                    }
                }
                require(found, string(abi.encodePacked("New member not found in old SecurityCouncil: ", vm.toString(_newMembers[i]))));
            }
            console2.log("All new members verified as existing SecurityCouncil members");
        }

        // Sort new members (required by Multisig constructor)
        _newMembers = Utils.sortAddresses(_newMembers);
        require(_newMembers.length == 8, "Must provide exactly 8 members");

        console2.log("");
        console2.log("=== New SecurityCouncil Members (sorted) ===");
        for (uint256 i = 0; i < _newMembers.length; i++) {
            console2.log(i, _newMembers[i]);
        }

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Deploy new SecurityCouncil
        vm.startBroadcast(deployerPrivateKey);
        SecurityCouncil newSecurityCouncil = new SecurityCouncil(
            IProtocolUpgradeHandler(_currentHandler),
            _newMembers
        );
        vm.stopBroadcast();

        // Deploy new EmergencyUpgradeBoard
        vm.startBroadcast(deployerPrivateKey);
        EmergencyUpgradeBoard newEmergencyUpgradeBoard = new EmergencyUpgradeBoard(
            IProtocolUpgradeHandler(_currentHandler),
            address(newSecurityCouncil),
            currentGuardians,
            zkFoundationSafe
        );
        vm.stopBroadcast();

        deployedAddresses = SCRedeployedContracts({
            securityCouncil: address(newSecurityCouncil),
            emergencyUpgradeBoard: address(newEmergencyUpgradeBoard)
        });

        console2.log("");
        console2.log("=== Newly Deployed Contracts ===");
        console2.log("New SecurityCouncil:", address(newSecurityCouncil));
        console2.log("New EmergencyUpgradeBoard:", address(newEmergencyUpgradeBoard));

        // Generate the Call[] that the ProtocolUpgradeHandler must execute
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](2);

        calls[0] = IProtocolUpgradeHandler.Call({
            target: _currentHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateSecurityCouncil, (address(newSecurityCouncil)))
        });

        calls[1] = IProtocolUpgradeHandler.Call({
            target: _currentHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (address(newEmergencyUpgradeBoard)))
        });

        bytes memory encodedCalls = abi.encode(calls);

        console2.log("");
        console2.log("=== Upgrade Calls for ProtocolUpgradeHandler ===");
        console2.log("Call[0]: updateSecurityCouncil ->", address(newSecurityCouncil));
        console2.log("Call[1]: updateEmergencyUpgradeBoard ->", address(newEmergencyUpgradeBoard));
        console2.log("");
        console2.log("abi.encode(Call[]):");
        console2.logBytes(encodedCalls);
    }
}
