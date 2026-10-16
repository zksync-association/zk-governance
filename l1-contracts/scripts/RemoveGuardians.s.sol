// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import "./ILegacyEmergencyUpgradeBoard.sol";
import "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {
    ProtocolUpgradeHandlerStateCheck,
    IProtocolUpgradeHandlerRoles
} from "../src/ProtocolUpgradeHandlerStateCheck.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

/// @dev Inputs of the guardians removal.
struct RemoveGuardiansParams {
    /// @dev The ProtocolUpgradeHandler proxy.
    address protocolUpgradeHandler;
    /// @dev The ProtocolUpgradeHandler roles the removal is built against, i.e. the state the
    /// v31 upgrade leaves behind. The generated proposal reverts unless they are in place.
    address expectedSecurityCouncil;
    address expectedGuardians;
    address expectedEmergencyUpgradeBoard;
    /// @dev The address that takes over the guardians role on the ProtocolUpgradeHandler
    /// (legal veto extension + upgrade approval), expected to be the ZK Foundation Safe.
    address newGuardians;
}

struct RemoveGuardiansDeployedContracts {
    address emergencyUpgradeBoard;
    address stateCheck;
}

/// @title RemoveGuardians
/// @notice Base script for removing the Guardians from the L1 side of ZKsync governance:
/// 1. Deploys (via CREATE2) the new two-party EmergencyUpgradeBoard (Security Council + ZK
///    Foundation), replacing the three-party board that also requires Guardians signatures,
///    and the ProtocolUpgradeHandlerStateCheck helper.
/// 2. Generates the Call[] for the ProtocolUpgradeHandler that
///    - checks that the handler roles are the expected (post-v31) ones,
///    - hands the guardians role (legal veto extension + upgrade approval) over to the
///      ZK Foundation multisig,
///    - switches to the new EmergencyUpgradeBoard.
///
/// The generated Call[] must be executed by the ProtocolUpgradeHandler itself, i.e. it is
/// meant to be included in a protocol upgrade proposal (ZIP). The leading state check makes
/// the proposal revert if it is executed before the v31 upgrade: v31 re-initializes the
/// handler roles, so executing the removal first would let v31 bring the Guardians back.
///
/// Optional env vars:
///   CREATE2_FACTORY    - CREATE2 deployer, defaults to the deterministic deployment proxy
///   CREATE2_SALT       - CREATE2 salt, defaults to zero
///   DEPLOY_OUTPUT_TOML - path to write the deployed addresses and the encoded Call[] to
contract RemoveGuardians is Script {
    address internal constant DETERMINISTIC_DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    RemoveGuardiansDeployedContracts internal deployedAddresses;
    IProtocolUpgradeHandler.Call[] internal generatedCalls;

    function getDeployedAddresses() public view returns (RemoveGuardiansDeployedContracts memory) {
        return deployedAddresses;
    }

    function getGeneratedCalls() public view returns (IProtocolUpgradeHandler.Call[] memory) {
        return generatedCalls;
    }

    /// @notice Main function.
    function runRemoveGuardians(RemoveGuardiansParams memory _params) internal {
        address zkFoundationSafe = _checkParams(_params);

        console2.log("=== Expected System State (post-v31) ===");
        console2.log("ProtocolUpgradeHandler:", _params.protocolUpgradeHandler);
        console2.log("SecurityCouncil:", _params.expectedSecurityCouncil);
        console2.log("Guardians:", _params.expectedGuardians);
        console2.log("EmergencyUpgradeBoard:", _params.expectedEmergencyUpgradeBoard);
        console2.log("ZK Foundation Safe:", zkFoundationSafe);
        console2.log("");
        console2.log("New guardians role holder:", _params.newGuardians);

        bytes32 salt = vm.envOr("CREATE2_SALT", bytes32(0));

        address newEmergencyUpgradeBoard = deployViaCreate2(
            abi.encodePacked(
                type(EmergencyUpgradeBoard).creationCode,
                abi.encode(
                    IProtocolUpgradeHandler(_params.protocolUpgradeHandler),
                    _params.expectedSecurityCouncil,
                    zkFoundationSafe
                )
            ),
            salt
        );
        address stateCheck = deployViaCreate2(type(ProtocolUpgradeHandlerStateCheck).creationCode, salt);

        deployedAddresses = RemoveGuardiansDeployedContracts({
            emergencyUpgradeBoard: newEmergencyUpgradeBoard,
            stateCheck: stateCheck
        });

        console2.log("");
        console2.log("=== Deployed Contracts ===");
        console2.log("New EmergencyUpgradeBoard (2/2):", newEmergencyUpgradeBoard);
        console2.log("ProtocolUpgradeHandlerStateCheck:", stateCheck);

        // Generate the Call[] that the ProtocolUpgradeHandler must execute
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](3);

        calls[0] = IProtocolUpgradeHandler.Call({
            target: stateCheck,
            value: 0,
            data: abi.encodeCall(
                ProtocolUpgradeHandlerStateCheck.checkRoles,
                (
                    IProtocolUpgradeHandlerRoles(_params.protocolUpgradeHandler),
                    _params.expectedSecurityCouncil,
                    _params.expectedGuardians,
                    _params.expectedEmergencyUpgradeBoard
                )
            )
        });

        calls[1] = IProtocolUpgradeHandler.Call({
            target: _params.protocolUpgradeHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateGuardians, (_params.newGuardians))
        });

        calls[2] = IProtocolUpgradeHandler.Call({
            target: _params.protocolUpgradeHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (newEmergencyUpgradeBoard))
        });

        delete generatedCalls;
        for (uint256 i = 0; i < calls.length; i++) {
            generatedCalls.push(calls[i]);
        }

        bytes memory encodedCalls = abi.encode(calls);

        console2.log("");
        console2.log("=== Upgrade Calls for ProtocolUpgradeHandler ===");
        console2.log("Call[0]: checkRoles (post-v31 state) ->", stateCheck);
        console2.log("Call[1]: updateGuardians ->", _params.newGuardians);
        console2.log("Call[2]: updateEmergencyUpgradeBoard ->", newEmergencyUpgradeBoard);
        console2.log("");
        console2.log("abi.encode(Call[]):");
        console2.logBytes(encodedCalls);

        _writeOutput(newEmergencyUpgradeBoard, stateCheck, encodedCalls);
    }

    /// @dev Cross-checks the inputs against the expected EmergencyUpgradeBoard and returns the
    /// ZK Foundation Safe registered in it.
    function _checkParams(RemoveGuardiansParams memory _params) internal view returns (address zkFoundationSafe) {
        // The expected board is the three-party one, so it still exposes `GUARDIANS()`.
        EmergencyUpgradeBoard expectedBoard = EmergencyUpgradeBoard(_params.expectedEmergencyUpgradeBoard);
        require(
            address(expectedBoard.PROTOCOL_UPGRADE_HANDLER()) == _params.protocolUpgradeHandler,
            "Expected board is wired to a different handler"
        );
        require(
            expectedBoard.SECURITY_COUNCIL() == _params.expectedSecurityCouncil,
            "Expected board is wired to a different Security Council"
        );
        require(
            ILegacyEmergencyUpgradeBoard(address(expectedBoard)).GUARDIANS() == _params.expectedGuardians,
            "Expected board is wired to different Guardians"
        );
        zkFoundationSafe = expectedBoard.ZK_FOUNDATION_SAFE();
        require(zkFoundationSafe.code.length != 0, "ZK Foundation Safe must be a contract (multisig)");

        require(_params.newGuardians != address(0), "New guardians address is zero");
        require(_params.newGuardians != _params.expectedGuardians, "New guardians must differ from the current Guardians");
        require(_params.newGuardians.code.length != 0, "New guardians must be a contract (multisig)");
    }

    function deployViaCreate2(bytes memory _bytecode, bytes32 _salt) internal returns (address) {
        require(_bytecode.length != 0, "Bytecode is not set");
        address factory = vm.envOr("CREATE2_FACTORY", DETERMINISTIC_DEPLOYMENT_PROXY);
        address contractAddress = vm.computeCreate2Address(_salt, keccak256(_bytecode), factory);
        if (contractAddress.code.length != 0) {
            return contractAddress;
        }
        vm.broadcast();
        (bool success, bytes memory data) = factory.call(abi.encodePacked(_salt, _bytecode));
        require(
            success && bytesToAddress(data) == contractAddress && contractAddress.code.length != 0,
            "Failed to deploy contract via create2"
        );
        return contractAddress;
    }

    function bytesToAddress(bytes memory data) internal pure returns (address addr) {
        require(data.length >= 20, "Invalid address data");
        assembly {
            addr := mload(add(data, 20))
        }
    }

    function _writeOutput(address _newEmergencyUpgradeBoard, address _stateCheck, bytes memory _encodedCalls)
        internal
    {
        string memory outPath = vm.envOr("DEPLOY_OUTPUT_TOML", string(""));
        if (bytes(outPath).length == 0) {
            return;
        }
        vm.serializeAddress("deploy", "new_emergency_upgrade_board", _newEmergencyUpgradeBoard);
        vm.serializeAddress("deploy", "state_check", _stateCheck);
        string memory toml = vm.serializeBytes("deploy", "governance_calls", _encodedCalls);
        vm.writeToml(toml, outPath);
    }
}
