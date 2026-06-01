// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Multisig} from "../src/Multisig.sol";
import {Guardians} from "../src/Guardians.sol";
import {SecurityCouncil} from "../src/SecurityCouncil.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

/// @title DeployPUHAndGuardians
/// @notice Redeploys the full ProtocolUpgradeHandler governance set — the PUH
///         implementation, Guardians, SecurityCouncil and EmergencyUpgradeBoard
///         (all with the v31-era constructor signatures) — via CREATE2 against
///         an anvil fork. Reads ctor inputs from env vars + getters on the
///         previously-deployed PUH proxy. Logs the deployed addresses so the
///         caller (protocol-ops `ecosystem upgrade-prepare-all`) can encode the
///         governance Call[] that wires them in.
///
/// @dev Why the whole set, not just the PUH impl + Guardians: the
///      EmergencyUpgradeBoard bakes in the SecurityCouncil and Guardians
///      addresses as immutables. Redeploying Guardians (or SecurityCouncil)
///      without also redeploying the board would leave the board pointing at
///      the stale contracts — an inconsistency. So we always redeploy all four
///      together and wire the new board at the new SecurityCouncil + Guardians.
///
/// @dev On testnet ecosystems (stage / sepolia) we deploy the
///      `TestnetProtocolUpgradeHandler`, which zeroes the legal-veto and
///      upgrade-delay periods so upgrades don't wait days. On mainnet we deploy
///      the real `ProtocolUpgradeHandler`. The selection is driven by
///      `USE_TESTNET_PUH` (see env vars below).
///
/// @dev Required env vars:
///   - PREV_PROTOCOL_UPGRADE_HANDLER : current PUH proxy address
///   - CHAIN_ASSET_HANDLER           : new ChainAssetHandler proxy (from v31)
///   - ZKSYNC_OS_CHAIN_TYPE_MANAGER  : new ZKsync OS CTM address (from v31);
///         the old PUH has no getter for this so it must be passed explicitly.
///   - CREATE2_FACTORY               : CREATE2 deployer factory address
///   - CREATE2_SALT_GOV              : shared CREATE2 salt for all four
///         redeployed contracts (PUH impl, Guardians, SecurityCouncil,
///         EmergencyUpgradeBoard). Each has distinct init code, so one salt
///         still yields four distinct, collision-free addresses — and the whole
///         set rotates together with a single value.
///   - ERA_CHAIN_ID                  : Era chain ID (e.g. 270 stage, 324 mainnet)
///         The current PUH on stage/mainnet pre-dates the addition of
///         `ERA_CHAIN_ID` as a getter, so we must pass it explicitly.
///   - USE_TESTNET_PUH               : (optional, default false) when true,
///         deploy `TestnetProtocolUpgradeHandler` instead of the real one.
///   - DEPLOY_OUTPUT_TOML            : (optional) absolute path to write a TOML
///         with the deployed addresses; consumed by `protocol-ops` to encode
///         the governance Call[].
contract DeployPUHAndGuardians is Script {
    function bytesToAddress(bytes memory data) internal pure returns (address addr) {
        require(data.length >= 20, "Invalid address data");
        assembly {
            addr := mload(add(data, 20))
        }
    }

    function deployViaCreate2(bytes memory _bytecode, bytes32 _salt) internal returns (address) {
        require(_bytecode.length != 0, "Bytecode is not set");
        address factory = vm.envAddress("CREATE2_FACTORY");
        address contractAddress = vm.computeCreate2Address(_salt, keccak256(_bytecode), factory);
        if (contractAddress.code.length != 0) {
            return contractAddress;
        }
        vm.broadcast();
        (bool success, bytes memory data) = factory.call(abi.encodePacked(_salt, _bytecode));
        contractAddress = bytesToAddress(data);
        require(
            success && contractAddress != address(0) && contractAddress.code.length != 0,
            "Failed to deploy contract via create2"
        );
        return contractAddress;
    }

    /// @dev Reads the member list of a Multisig (Guardians / SecurityCouncil).
    ///      `members` is the first storage variable (slot 0 holds the array
    ///      length) for both contracts since they inherit from `Multisig`.
    function _readMembers(address _multisig) internal view returns (address[] memory members) {
        uint256 totalMembers = uint256(vm.load(_multisig, 0));
        require(totalMembers != 0, "Multisig has no members");
        members = new address[](totalMembers);
        for (uint256 i = 0; i < totalMembers; i++) {
            members[i] = Multisig(_multisig).members(i);
            require(members[i] != address(0), "Empty multisig member");
        }
    }

    function _prevHandler() internal view returns (ProtocolUpgradeHandler) {
        return ProtocolUpgradeHandler(payable(vm.envAddress("PREV_PROTOCOL_UPGRADE_HANDLER")));
    }

    /// @dev Single CREATE2 salt shared by all four redeployed contracts. They
    ///      have distinct init code, so one salt is collision-free and rotates
    ///      the whole governance set together.
    function _govSalt() internal view returns (bytes32) {
        return vm.envBytes32("CREATE2_SALT_GOV");
    }

    /// @dev Deploys the new PUH implementation. The Testnet variant shares the
    ///      real handler's constructor signature (it only overrides the
    ///      veto/delay period getters), so the encoded ctor args are identical
    ///      for both — we just swap the creation code.
    function _deployPuhImpl() internal returns (address) {
        ProtocolUpgradeHandler prev = _prevHandler();
        bytes memory ctorArgs = abi.encode(
            prev.L2_PROTOCOL_GOVERNOR(),
            prev.CHAIN_TYPE_MANAGER(),
            IChainTypeManager(vm.envAddress("ZKSYNC_OS_CHAIN_TYPE_MANAGER")),
            prev.BRIDGE_HUB(),
            prev.L1_NULLIFIER(),
            prev.L1_ASSET_ROUTER(),
            prev.L1_NATIVE_TOKEN_VAULT(),
            IChainAssetHandler(vm.envAddress("CHAIN_ASSET_HANDLER")),
            vm.envUint("ERA_CHAIN_ID")
        );
        bytes memory creationCode = vm.envOr("USE_TESTNET_PUH", false)
            ? type(TestnetProtocolUpgradeHandler).creationCode
            : type(ProtocolUpgradeHandler).creationCode;
        return deployViaCreate2(abi.encodePacked(creationCode, ctorArgs), _govSalt());
    }

    function _deployGuardians() internal returns (address) {
        ProtocolUpgradeHandler prev = _prevHandler();
        bytes memory ctorArgs = abi.encode(
            IProtocolUpgradeHandler(address(prev)),
            prev.BRIDGE_HUB(),
            vm.envUint("ERA_CHAIN_ID"),
            _readMembers(prev.guardians())
        );
        return
            deployViaCreate2(abi.encodePacked(type(Guardians).creationCode, ctorArgs), _govSalt());
    }

    function _deploySecurityCouncil() internal returns (address) {
        ProtocolUpgradeHandler prev = _prevHandler();
        bytes memory ctorArgs = abi.encode(
            IProtocolUpgradeHandler(address(prev)),
            _readMembers(prev.securityCouncil())
        );
        return
            deployViaCreate2(abi.encodePacked(type(SecurityCouncil).creationCode, ctorArgs), _govSalt());
    }

    /// @dev Wires the new board at the freshly deployed SecurityCouncil +
    ///      Guardians so it can never dangle against stale contracts. The ZK
    ///      Foundation safe is preserved from the existing board.
    function _deployEmergencyUpgradeBoard(
        address _newSecurityCouncil,
        address _newGuardians
    ) internal returns (address) {
        ProtocolUpgradeHandler prev = _prevHandler();
        address zkFoundationSafe = EmergencyUpgradeBoard(prev.emergencyUpgradeBoard()).ZK_FOUNDATION_SAFE();
        bytes memory ctorArgs = abi.encode(
            IProtocolUpgradeHandler(address(prev)),
            _newSecurityCouncil,
            _newGuardians,
            zkFoundationSafe
        );
        return
            deployViaCreate2(abi.encodePacked(type(EmergencyUpgradeBoard).creationCode, ctorArgs), _govSalt());
    }

    function _writeOutput(
        address _newPuhImpl,
        address _newGuardians,
        address _newSecurityCouncil,
        address _newEmergencyUpgradeBoard
    ) internal {
        try vm.envString("DEPLOY_OUTPUT_TOML") returns (string memory outPath) {
            if (bytes(outPath).length > 0) {
                vm.serializeAddress("deploy", "new_puh_impl", _newPuhImpl);
                vm.serializeAddress("deploy", "new_guardians", _newGuardians);
                vm.serializeAddress("deploy", "new_security_council", _newSecurityCouncil);
                string memory toml = vm.serializeAddress(
                    "deploy",
                    "new_emergency_upgrade_board",
                    _newEmergencyUpgradeBoard
                );
                vm.writeToml(toml, outPath);
            }
        } catch {
            // env var not set — skip
        }
    }

    function run() external {
        address newPuhImpl = _deployPuhImpl();
        address newGuardians = _deployGuardians();
        address newSecurityCouncil = _deploySecurityCouncil();
        address newEmergencyUpgradeBoard = _deployEmergencyUpgradeBoard(newSecurityCouncil, newGuardians);

        console2.log("ProtocolUpgradeHandler impl deployed at:", newPuhImpl);
        console2.log("Testnet handler:", vm.envOr("USE_TESTNET_PUH", false));
        console2.log("Guardians deployed at:", newGuardians);
        console2.log("SecurityCouncil deployed at:", newSecurityCouncil);
        console2.log("EmergencyUpgradeBoard deployed at:", newEmergencyUpgradeBoard);

        _writeOutput(newPuhImpl, newGuardians, newSecurityCouncil, newEmergencyUpgradeBoard);
    }
}
