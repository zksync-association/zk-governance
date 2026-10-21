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
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";

/// @dev The state of the ProtocolUpgradeHandler the removal is built against, read from the proxy.
struct RemoveGuardiansHandlerState {
    address proxyAdmin;
    /// @dev The new implementation copies its constructor arguments (immutables) from it.
    address implementation;
    /// @dev The generated proposal reverts unless the handler still holds these roles.
    address securityCouncil;
    address emergencyUpgradeBoard;
    /// @dev The ZK Foundation Safe registered in the current EmergencyUpgradeBoard.
    address zkFoundationSafe;
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
/// The only input is the ProtocolUpgradeHandler proxy: the proxy admin, the implementation
/// whose immutables are copied, the roles and the ZK Foundation Safe are all read from it. The
/// script must therefore run once v31 is executed, and refuses to run before.
///
/// The generated Call[] must be executed by the ProtocolUpgradeHandler itself, i.e. it is
/// meant to be included in a protocol upgrade proposal (ZIP). The leading state check makes
/// the proposal revert unless the handler still holds the roles it was built against. This
/// also keeps the ordering when the proposal is built on a fork that replays v31: v31
/// re-initializes the handler, so executing the removal first would let v31 bring the
/// Guardians back.
///
/// Optional env vars:
///   CREATE2_FACTORY    - CREATE2 deployer, defaults to the deterministic deployment proxy
///   CREATE2_SALT       - CREATE2 salt, defaults to zero
///   DEPLOY_OUTPUT_TOML - path to write the deployed addresses and the encoded Call[] to
contract RemoveGuardians is Script {
    address internal constant DETERMINISTIC_DEPLOYMENT_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev L1Messenger system contract on Era, used by the ZIP to send the proposal to L1.
    address internal constant L1_MESSENGER = 0x0000000000000000000000000000000000008008;

    /// @dev EIP-1967 admin slot, `bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)`.
    bytes32 internal constant PROXY_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @dev EIP-1967 implementation slot, `bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1)`.
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    RemoveGuardiansDeployedContracts internal deployedAddresses;
    IProtocolUpgradeHandler.Call[] internal generatedCalls;

    function getDeployedAddresses() public view returns (RemoveGuardiansDeployedContracts memory) {
        return deployedAddresses;
    }

    function getGeneratedCalls() public view returns (IProtocolUpgradeHandler.Call[] memory) {
        return generatedCalls;
    }

    /// @notice Main function.
    /// @param _protocolUpgradeHandler The ProtocolUpgradeHandler proxy.
    /// @param _useTestnetHandler Whether to deploy the TestnetProtocolUpgradeHandler (zero legal
    /// veto / delay periods).
    function runRemoveGuardians(address _protocolUpgradeHandler, bool _useTestnetHandler) internal {
        RemoveGuardiansHandlerState memory state = _readHandlerState(_protocolUpgradeHandler);

        console2.log("=== Current System State (post-v31) ===");
        console2.log("ProtocolUpgradeHandler:", _protocolUpgradeHandler);
        console2.log("ProtocolUpgradeHandler ProxyAdmin:", state.proxyAdmin);
        console2.log("ProtocolUpgradeHandler implementation:", state.implementation);
        console2.log("SecurityCouncil:", state.securityCouncil);
        console2.log("EmergencyUpgradeBoard:", state.emergencyUpgradeBoard);
        console2.log("");
        console2.log("New ZK Foundation role holder:", state.zkFoundationSafe);

        bytes32 salt = vm.envOr("CREATE2_SALT", bytes32(0));

        address newImplementation =
            deployViaCreate2(_implementationCreationCode(state.implementation, _useTestnetHandler), salt);
        address newEmergencyUpgradeBoard = deployViaCreate2(
            abi.encodePacked(
                type(EmergencyUpgradeBoard).creationCode,
                abi.encode(
                    IProtocolUpgradeHandler(_protocolUpgradeHandler), state.securityCouncil, state.zkFoundationSafe
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
                    IProtocolUpgradeHandlerRoles(_protocolUpgradeHandler),
                    state.securityCouncil,
                    state.emergencyUpgradeBoard
                )
            )
        });

        // No re-initialization: the proxy is already initialized (by v31) at the version of
        // `initialize`, the roles are rotated by the self-calls below.
        calls[1] = IProtocolUpgradeHandler.Call({
            target: state.proxyAdmin,
            value: 0,
            data: abi.encodeCall(
                ProxyAdmin.upgradeAndCall,
                (ITransparentUpgradeableProxy(_protocolUpgradeHandler), newImplementation, bytes(""))
            )
        });

        calls[2] = IProtocolUpgradeHandler.Call({
            target: _protocolUpgradeHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateZkFoundation, (state.zkFoundationSafe))
        });

        calls[3] = IProtocolUpgradeHandler.Call({
            target: _protocolUpgradeHandler,
            value: 0,
            data: abi.encodeCall(ProtocolUpgradeHandler.updateEmergencyUpgradeBoard, (newEmergencyUpgradeBoard))
        });

        delete generatedCalls;
        for (uint256 i = 0; i < calls.length; i++) {
            generatedCalls.push(calls[i]);
        }

        bytes memory encodedCalls = abi.encode(calls);

        // The ZIP on the ZkProtocolGovernor sends the proposal to L1 via the L1Messenger, which
        // the ProtocolUpgradeHandler then reads in `startUpgrade`. Same shape as v31: anyone can
        // execute it (no executor) and the salt is zero.
        IProtocolUpgradeHandler.UpgradeProposal memory proposal =
            IProtocolUpgradeHandler.UpgradeProposal({calls: calls, executor: address(0), salt: bytes32(0)});
        bytes memory l2Calldata = abi.encodeWithSignature("sendToL1(bytes)", abi.encode(proposal));
        bytes32 upgradeId = keccak256(abi.encode(proposal));

        console2.log("");
        console2.log("=== Upgrade Calls for ProtocolUpgradeHandler ===");
        console2.log("Call[0]: checkRoles (post-v31 state) ->", stateCheck);
        console2.log("Call[1]: ProxyAdmin.upgradeAndCall ->", newImplementation);
        console2.log("Call[2]: updateZkFoundation ->", state.zkFoundationSafe);
        console2.log("Call[3]: updateEmergencyUpgradeBoard ->", newEmergencyUpgradeBoard);
        console2.log("");
        console2.log("abi.encode(Call[]):");
        console2.logBytes(encodedCalls);
        console2.log("");
        console2.log("=== ZIP (ZkProtocolGovernor proposal action) ===");
        console2.log("target:", L1_MESSENGER);
        console2.log("value: 0");
        console2.log("calldata:");
        console2.logBytes(l2Calldata);
        console2.log("Upgrade id (ProtocolUpgradeHandler):");
        console2.logBytes32(upgradeId);

        _writeOutput(newImplementation, newEmergencyUpgradeBoard, stateCheck, encodedCalls, l2Calldata, upgradeId);
    }

    /// @dev Reads the state the removal is built against from the proxy and cross-checks it.
    function _readHandlerState(address _protocolUpgradeHandler)
        internal
        view
        returns (RemoveGuardiansHandlerState memory state)
    {
        ProtocolUpgradeHandler handler = ProtocolUpgradeHandler(payable(_protocolUpgradeHandler));
        // The guardians removal implementation exposes `zkFoundation()` in place of `guardians()`.
        try handler.zkFoundation() returns (address) {
            revert("Guardians are already removed");
        } catch {}

        state.implementation = address(uint160(uint256(vm.load(_protocolUpgradeHandler, IMPLEMENTATION_SLOT))));
        // Getter introduced by v31: the immutables of an older implementation can't be copied.
        try ProtocolUpgradeHandler(payable(state.implementation)).ZKSYNC_OS_CHAIN_TYPE_MANAGER() returns (
            IChainTypeManager
        ) {} catch {
            revert("The handler must run the v31 implementation");
        }

        state.proxyAdmin = address(uint160(uint256(vm.load(_protocolUpgradeHandler, PROXY_ADMIN_SLOT))));
        require(
            ProxyAdmin(state.proxyAdmin).owner() == _protocolUpgradeHandler, "ProxyAdmin must be owned by the handler"
        );

        state.securityCouncil = handler.securityCouncil();
        state.emergencyUpgradeBoard = handler.emergencyUpgradeBoard();
        EmergencyUpgradeBoard board = EmergencyUpgradeBoard(state.emergencyUpgradeBoard);
        require(
            address(board.PROTOCOL_UPGRADE_HANDLER()) == _protocolUpgradeHandler,
            "Current board is wired to a different handler"
        );
        require(
            board.SECURITY_COUNCIL() == state.securityCouncil, "Current board is wired to a different Security Council"
        );
        state.zkFoundationSafe = board.ZK_FOUNDATION_SAFE();
        require(state.zkFoundationSafe.code.length != 0, "ZK Foundation Safe must be a contract (multisig)");
    }

    /// @dev The new implementation keeps every immutable of the current one.
    function _implementationCreationCode(address _currentImplementation, bool _useTestnetHandler)
        internal
        view
        returns (bytes memory)
    {
        ProtocolUpgradeHandler currentImplementation = ProtocolUpgradeHandler(payable(_currentImplementation));
        bytes memory constructorArgs = abi.encode(
            currentImplementation.L2_PROTOCOL_GOVERNOR(),
            currentImplementation.ERA_CHAIN_TYPE_MANAGER(),
            currentImplementation.ZKSYNC_OS_CHAIN_TYPE_MANAGER(),
            currentImplementation.BRIDGE_HUB(),
            currentImplementation.L1_NULLIFIER(),
            currentImplementation.L1_ASSET_ROUTER(),
            currentImplementation.L1_NATIVE_TOKEN_VAULT(),
            currentImplementation.CHAIN_ASSET_HANDLER(),
            currentImplementation.ERA_CHAIN_ID()
        );
        bytes memory creationCode = _useTestnetHandler
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
        bytes memory _encodedCalls,
        bytes memory _l2Calldata,
        bytes32 _upgradeId
    ) internal {
        string memory outPath = vm.envOr("DEPLOY_OUTPUT_TOML", string(""));
        if (bytes(outPath).length == 0) {
            return;
        }
        vm.serializeAddress("deploy", "new_puh_impl", _newImplementation);
        vm.serializeAddress("deploy", "new_emergency_upgrade_board", _newEmergencyUpgradeBoard);
        vm.serializeAddress("deploy", "state_check", _stateCheck);
        vm.serializeBytes("deploy", "governance_calls", _encodedCalls);
        vm.serializeAddress("deploy", "zip_target", L1_MESSENGER);
        vm.serializeBytes("deploy", "zip_calldata", _l2Calldata);
        string memory toml = vm.serializeBytes32("deploy", "upgrade_id", _upgradeId);
        vm.writeToml(toml, outPath);
    }
}
