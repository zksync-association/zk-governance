// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {console2} from "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";
import {
    ProtocolUpgradeHandlerStateCheck,
    IProtocolUpgradeHandlerRoles
} from "../src/ProtocolUpgradeHandlerStateCheck.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

/// @dev Inputs of the guardians removal.
struct RemoveGuardiansParams {
    /// @dev The ProtocolUpgradeHandler proxy.
    address protocolUpgradeHandler;
    /// @dev The ProtocolUpgradeHandler implementation installed by v31. The new implementation
    /// copies its constructor arguments (immutables) from it.
    address v31Implementation;
    /// @dev Whether to deploy the TestnetProtocolUpgradeHandler (zero legal veto / delay periods).
    bool useTestnetHandler;
    /// @dev The ProtocolUpgradeHandler roles the removal is built against, i.e. the state the
    /// v31 upgrade leaves behind. The generated proposal reverts unless they are in place.
    address expectedSecurityCouncil;
    address expectedEmergencyUpgradeBoard;
}

struct RemoveGuardiansDeployedContracts {
    address protocolUpgradeHandlerImpl;
    address emergencyUpgradeBoard;
    address stateCheck;
}

/// @title RemoveGuardians
/// @notice Base script for removing the Guardians from the L1 side of ZKsync governance:
/// 1. Deploys (via CREATE2)
///    - the new ProtocolUpgradeHandler implementation, where the role previously held by the
///      Guardians (legal veto extension + upgrade approval) belongs to the ZK Foundation,
///    - the new two-party EmergencyUpgradeBoard (Security Council + ZK Foundation), replacing
///      the three-party board that also requires Guardians signatures,
///    - the ProtocolUpgradeHandlerStateCheck helper.
/// 2. Generates the Call[] for the ProtocolUpgradeHandler that
///    - checks that the handler roles are the expected (post-v31) ones,
///    - upgrades the ProtocolUpgradeHandler proxy to the new implementation,
///    - hands the ZK Foundation role to the ZK Foundation Safe of the current board,
///    - switches to the new EmergencyUpgradeBoard.
///
/// The generated Call[] must be executed by the ProtocolUpgradeHandler itself, i.e. it is
/// meant to be included in a protocol upgrade proposal (ZIP). The leading state check makes
/// the proposal revert if it is executed before the v31 upgrade: v31 re-initializes the
/// handler, so executing the removal first would let v31 bring the Guardians back.
///
/// Optional env vars:
///   CREATE2_FACTORY    - CREATE2 deployer, defaults to the deterministic deployment proxy
///   CREATE2_SALT       - CREATE2 salt, defaults to zero
///   DEPLOY_OUTPUT_TOML - path to write the deployed addresses and the encoded Call[] to
contract RemoveGuardians is Script {
    address internal constant DETERMINISTIC_DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev EIP-1967 admin slot, `bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)`.
    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

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
        (address zkFoundationSafe, address proxyAdmin) = _checkParams(_params);

        console2.log("=== Expected System State (post-v31) ===");
        console2.log("ProtocolUpgradeHandler:", _params.protocolUpgradeHandler);
        console2.log("ProtocolUpgradeHandler ProxyAdmin:", proxyAdmin);
        console2.log("v31 ProtocolUpgradeHandler implementation:", _params.v31Implementation);
        console2.log("SecurityCouncil:", _params.expectedSecurityCouncil);
        console2.log("EmergencyUpgradeBoard:", _params.expectedEmergencyUpgradeBoard);
        console2.log("");
        console2.log("New ZK Foundation role holder:", zkFoundationSafe);

        bytes32 salt = vm.envOr("CREATE2_SALT", bytes32(0));

        address newImplementation = deployViaCreate2(_implementationCreationCode(_params), salt);
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
            protocolUpgradeHandlerImpl: newImplementation,
            emergencyUpgradeBoard: newEmergencyUpgradeBoard,
            stateCheck: stateCheck
        });

        console2.log("");
        console2.log("=== Deployed Contracts ===");
        console2.log("New ProtocolUpgradeHandler implementation:", newImplementation);
        console2.log("New EmergencyUpgradeBoard (2/2):", newEmergencyUpgradeBoard);
        console2.log("ProtocolUpgradeHandlerStateCheck:", stateCheck);

        // Generate the Call[] that the ProtocolUpgradeHandler must execute
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](4);

        calls[0] = IProtocolUpgradeHandler.Call({
            target: stateCheck,
            value: 0,
            data: abi.encodeCall(
                ProtocolUpgradeHandlerStateCheck.checkRoles,
                (
                    IProtocolUpgradeHandlerRoles(_params.protocolUpgradeHandler),
                    _params.expectedSecurityCouncil,
                    _params.expectedEmergencyUpgradeBoard
                )
            )
        });

        // No re-initialization: the proxy is already initialized (by v31) at the version of
        // `initialize`, the roles are rotated by the self-calls below.
        calls[1] = IProtocolUpgradeHandler.Call({
            target: proxyAdmin,
            value: 0,
            data: abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(_params.protocolUpgradeHandler), newImplementation, bytes(""))
            )
        });

        calls[2] = IProtocolUpgradeHandler.Call({
            target: _params.protocolUpgradeHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateZkFoundation, (zkFoundationSafe))
        });

        calls[3] = IProtocolUpgradeHandler.Call({
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
        console2.log("Call[1]: ProxyAdmin.upgradeAndCall ->", newImplementation);
        console2.log("Call[2]: updateZkFoundation ->", zkFoundationSafe);
        console2.log("Call[3]: updateEmergencyUpgradeBoard ->", newEmergencyUpgradeBoard);
        console2.log("");
        console2.log("abi.encode(Call[]):");
        console2.logBytes(encodedCalls);

        _writeOutput(newImplementation, newEmergencyUpgradeBoard, stateCheck, encodedCalls);
    }

    /// @dev Cross-checks the inputs against the expected EmergencyUpgradeBoard and the proxy, and
    /// returns the ZK Foundation Safe registered in the board and the proxy admin of the handler.
    function _checkParams(RemoveGuardiansParams memory _params)
        internal
        view
        returns (address zkFoundationSafe, address proxyAdmin)
    {
        EmergencyUpgradeBoard expectedBoard = EmergencyUpgradeBoard(_params.expectedEmergencyUpgradeBoard);
        require(
            address(expectedBoard.PROTOCOL_UPGRADE_HANDLER()) == _params.protocolUpgradeHandler,
            "Expected board is wired to a different handler"
        );
        require(
            expectedBoard.SECURITY_COUNCIL() == _params.expectedSecurityCouncil,
            "Expected board is wired to a different Security Council"
        );
        zkFoundationSafe = expectedBoard.ZK_FOUNDATION_SAFE();
        require(zkFoundationSafe.code.length != 0, "ZK Foundation Safe must be a contract (multisig)");

        proxyAdmin = address(uint160(uint256(vm.load(_params.protocolUpgradeHandler, PROXY_ADMIN_SLOT))));
        require(
            ProxyAdmin(proxyAdmin).owner() == _params.protocolUpgradeHandler,
            "ProxyAdmin must be owned by the handler"
        );
    }

    /// @dev The new implementation keeps every immutable of the v31 one.
    function _implementationCreationCode(RemoveGuardiansParams memory _params) internal view returns (bytes memory) {
        ProtocolUpgradeHandler v31Implementation = ProtocolUpgradeHandler(payable(_params.v31Implementation));
        bytes memory constructorArgs = abi.encode(
            v31Implementation.L2_PROTOCOL_GOVERNOR(),
            v31Implementation.ERA_CHAIN_TYPE_MANAGER(),
            v31Implementation.ZKSYNC_OS_CHAIN_TYPE_MANAGER(),
            v31Implementation.BRIDGE_HUB(),
            v31Implementation.L1_NULLIFIER(),
            v31Implementation.L1_ASSET_ROUTER(),
            v31Implementation.L1_NATIVE_TOKEN_VAULT(),
            v31Implementation.CHAIN_ASSET_HANDLER(),
            v31Implementation.ERA_CHAIN_ID()
        );
        bytes memory creationCode = _params.useTestnetHandler
            ? type(TestnetProtocolUpgradeHandler).creationCode
            : type(ProtocolUpgradeHandler).creationCode;
        return abi.encodePacked(creationCode, constructorArgs);
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

    function _writeOutput(
        address _newImplementation,
        address _newEmergencyUpgradeBoard,
        address _stateCheck,
        bytes memory _encodedCalls
    ) internal {
        string memory outPath = vm.envOr("DEPLOY_OUTPUT_TOML", string(""));
        if (bytes(outPath).length == 0) {
            return;
        }
        vm.serializeAddress("deploy", "new_puh_impl", _newImplementation);
        vm.serializeAddress("deploy", "new_emergency_upgrade_board", _newEmergencyUpgradeBoard);
        vm.serializeAddress("deploy", "state_check", _stateCheck);
        string memory toml = vm.serializeBytes("deploy", "governance_calls", _encodedCalls);
        vm.writeToml(toml, outPath);
    }
}
