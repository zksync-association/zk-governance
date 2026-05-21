// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Multisig} from "../src/Multisig.sol";
import {Guardians} from "../src/Guardians.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";

/// @title DeployPUHAndGuardians
/// @notice Deploys the new ProtocolUpgradeHandler implementation and a new
///         Guardians contract (both with the v31-era constructor signatures)
///         via CREATE2 against an anvil fork. Reads ctor inputs from env vars
///         + getters on the previously-deployed PUH proxy. Logs the two
///         deployed addresses so the caller (protocol-ops `gov upgrade-puh`)
///         can encode the governance Call[] that wires them in.
///
/// @dev Required env vars:
///   - PREV_PROTOCOL_UPGRADE_HANDLER : current PUH proxy address
///   - CHAIN_ASSET_HANDLER           : new ChainAssetHandler proxy (from v31)
///   - CREATE2_FACTORY               : CREATE2 deployer factory address
///   - CREATE2_SALT_PUH              : salt for the new PUH impl
///   - CREATE2_SALT_GUARDIANS        : salt for the new Guardians
///   - ERA_CHAIN_ID                  : Era chain ID (e.g. 270 stage, 324 mainnet)
///         The current PUH on stage/mainnet pre-dates the addition of
///         `ERA_CHAIN_ID` as a getter, so we must pass it explicitly.
///   - DEPLOY_OUTPUT_TOML            : (optional) absolute path to write a TOML
///         with the two deployed addresses; consumed by `protocol-ops gov
///         upgrade-puh-guardians` to encode the governance Call[].
contract DeployPUHAndGuardians is Script {
    function bytesToAddress(bytes memory data) internal pure returns (address addr) {
        require(data.length >= 20, "Invalid address data");
        assembly {
            addr := mload(add(data, 20))
        }
    }

    function deployViaCreate2(
        bytes memory _bytecode,
        bytes32 _salt,
        address _factory
    ) internal returns (address) {
        require(_bytecode.length != 0, "Bytecode is not set");
        address contractAddress = vm.computeCreate2Address(_salt, keccak256(_bytecode), _factory);
        if (contractAddress.code.length != 0) {
            return contractAddress;
        }
        vm.broadcast();
        (bool success, bytes memory data) = _factory.call(abi.encodePacked(_salt, _bytecode));
        contractAddress = bytesToAddress(data);
        require(
            success && contractAddress != address(0) && contractAddress.code.length != 0,
            "Failed to deploy contract via create2"
        );
        return contractAddress;
    }

    function _readGuardiansMembers(address _guardians) internal view returns (address[] memory members) {
        // Multisig stores `members` as the first state variable; slot 0 holds the array length.
        uint256 totalMembers = uint256(vm.load(_guardians, 0));
        require(totalMembers == 8, "Existing Guardians must have exactly 8 members");
        members = new address[](totalMembers);
        for (uint256 i = 0; i < totalMembers; i++) {
            members[i] = Multisig(_guardians).members(i);
            require(members[i] != address(0), "Empty Guardians member");
        }
    }

    function run() external {
        address prevHandlerAddr = vm.envAddress("PREV_PROTOCOL_UPGRADE_HANDLER");
        address chainAssetHandlerAddr = vm.envAddress("CHAIN_ASSET_HANDLER");
        address create2FactoryAddr = vm.envAddress("CREATE2_FACTORY");
        bytes32 puhSalt = vm.envBytes32("CREATE2_SALT_PUH");
        bytes32 guardiansSalt = vm.envBytes32("CREATE2_SALT_GUARDIANS");
        uint256 chainId = vm.envUint("ERA_CHAIN_ID");

        ProtocolUpgradeHandler prev = ProtocolUpgradeHandler(payable(prevHandlerAddr));

        // ── PUH impl ─────────────────────────────────────────────────
        bytes memory puhBytecode = abi.encodePacked(
            type(ProtocolUpgradeHandler).creationCode,
            abi.encode(
                prev.L2_PROTOCOL_GOVERNOR(),
                prev.CHAIN_TYPE_MANAGER(),
                prev.BRIDGE_HUB(),
                prev.L1_NULLIFIER(),
                prev.L1_ASSET_ROUTER(),
                prev.L1_NATIVE_TOKEN_VAULT(),
                IChainAssetHandler(chainAssetHandlerAddr),
                chainId
            )
        );
        address newPuhImpl = deployViaCreate2(puhBytecode, puhSalt, create2FactoryAddr);

        // ── Guardians ────────────────────────────────────────────────
        address[] memory members = _readGuardiansMembers(prev.guardians());
        bytes memory guardiansBytecode = abi.encodePacked(
            type(Guardians).creationCode,
            abi.encode(IProtocolUpgradeHandler(prevHandlerAddr), prev.BRIDGE_HUB(), chainId, members)
        );
        address newGuardians = deployViaCreate2(guardiansBytecode, guardiansSalt, create2FactoryAddr);

        console2.log("ProtocolUpgradeHandler impl deployed at:", newPuhImpl);
        console2.log("Guardians deployed at:", newGuardians);

        // Optional: write addresses to a TOML so the calling tooling can pick
        // them up without parsing the broadcast log or stdout.
        try vm.envString("DEPLOY_OUTPUT_TOML") returns (string memory outPath) {
            if (bytes(outPath).length > 0) {
                vm.serializeAddress("deploy", "new_puh_impl", newPuhImpl);
                string memory toml = vm.serializeAddress("deploy", "new_guardians", newGuardians);
                vm.writeToml(toml, outPath);
            }
        } catch {
            // env var not set — skip
        }
    }
}
