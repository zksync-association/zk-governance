// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import {Utils} from "../scripts/Utils.sol";
import {ISafeSetup} from "../scripts/ISafeSetup.sol";
import {IGnosisSafeProxyFactory} from "../scripts/IGnosisSafeProxyFactory.sol";

import {SecurityCouncil} from "../src/SecurityCouncil.sol";
import {Guardians} from "../src/Guardians.sol";
import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {EmergencyUpgradeBoard} from "../src/EmergencyUpgradeBoard.sol";

import {IZKsyncEra} from "../src/interfaces/IZKsyncEra.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";

import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployL1Governance
/// @notice Deploys the full ZKsync L1 governance stack against a ZK chain registered on the
///         Sepolia testnet ecosystem, wired to an L2 protocol governor (the L2 timelock).
///
/// The members of the Security Council (12) and Guardians (8), and the ZK Foundation, are
/// deployed as single-owner Gnosis Safe (v1.3.0) multisigs whose sole owner is `SAFE_OWNER`.
/// This mirrors the mainnet sample where each council/guardian seat is a 1-of-1 Safe.
///
/// Required env:
///   PRIVATE_KEY            - deployer private key (uint)
///   L2_PROTOCOL_GOVERNOR   - the L2 timelock address that emits the L2->L1 upgrade message
///   SALT_BASE              - a uint nonce base making each run's Safe addresses unique
///   L1_OUT                 - path to write the resulting addresses JSON
/// Optional env (default to the chain-301 Sepolia ecosystem):
///   ZKSYNC_ERA, CHAIN_TYPE_MANAGER, BRIDGE_HUB, L1_NULLIFIER, L1_ASSET_ROUTER,
///   L1_NATIVE_TOKEN_VAULT, CHAIN_ASSET_HANDLER, SAFE_OWNER
contract DeployL1Governance is Script {
    // Canonical Gnosis Safe v1.3.0 addresses (identical on mainnet & Sepolia) -- the same
    // singleton/factory/fallback-handler used by the production council/guardian member safes.
    IGnosisSafeProxyFactory constant SAFE_PROXY_FACTORY =
        IGnosisSafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);
    address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
    address constant COMPATIBILITY_FALLBACK_HANDLER = 0xf48f2B2d2a534e402487b3ee7C18c33Aec0Fe5e4;

    function _env(string memory key, address dflt) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return dflt;
        }
    }

    function _deploySafe(address owner, uint256 saltNonce) internal returns (address) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        bytes memory initializer = abi.encodeCall(
            ISafeSetup.setup,
            (owners, 1, address(0), "", COMPATIBILITY_FALLBACK_HANDLER, address(0), 0, payable(address(0)))
        );
        return SAFE_PROXY_FACTORY.createProxyWithNonce(SAFE_SINGLETON, initializer, saltNonce);
    }

    struct Ecosystem {
        IZKsyncEra zksyncEra;
        IChainTypeManager ctm;
        IBridgeHub bridgeHub;
        IPausable l1Nullifier;
        IPausable l1AssetRouter;
        IPausable l1Ntv;
        IChainAssetHandler cah;
    }

    function _ecosystem() internal view returns (Ecosystem memory e) {
        // chain-301 Sepolia ecosystem defaults (overridable via env)
        e.zksyncEra = IZKsyncEra(_env("ZKSYNC_ERA", 0xD3bc4353957bc0F138318384aa207C708A9455C4));
        e.ctm = IChainTypeManager(_env("CHAIN_TYPE_MANAGER", 0x3Cc81628a14C824057a97C1B4Ab17758E5D18864));
        e.bridgeHub = IBridgeHub(_env("BRIDGE_HUB", 0xc4FD2580C3487bba18D63f50301020132342fdbD));
        e.l1Nullifier = IPausable(_env("L1_NULLIFIER", 0x9e24E2c23933d30eF2DEB70A0D977Fb1Ca20AbEa));
        e.l1AssetRouter = IPausable(_env("L1_ASSET_ROUTER", 0xB5d9C3F41E434b91295BD7962db5c873cEcCE2be));
        e.l1Ntv = IPausable(_env("L1_NATIVE_TOKEN_VAULT", 0xF8d4A5195737043f45F998539D5C62Eee02E3426));
        e.cah = IChainAssetHandler(_env("CHAIN_ASSET_HANDLER", 0xDfA2193b161d7bd45FC81b4E80225eebDc3CF96C));
    }

    struct Deployed {
        address puh;
        address impl;
        address proxyAdmin;
        address securityCouncil;
        address guardians;
        address board;
        address zkFoundation;
        address[] securityCouncilMembers;
        address[] guardiansMembers;
    }

    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function run() external {
        Ecosystem memory e = _ecosystem();
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPk);
        Deployed memory d = _deployMembers(_env("SAFE_OWNER", 0xD64e136566a9E04eb05B30184fF577F52682D182));
        _deployHandlerStack(e, d, vm.addr(deployerPk));
        vm.stopBroadcast();

        _report(d);
    }

    /// @dev Deploys the 12 SC + 8 guardian + 1 ZK foundation single-owner Safes.
    function _deployMembers(address safeOwner) internal returns (Deployed memory d) {
        uint256 saltBase = vm.envUint("SALT_BASE");
        d.securityCouncilMembers = new address[](12);
        for (uint256 i = 0; i < 12; ++i) {
            d.securityCouncilMembers[i] = _deploySafe(safeOwner, saltBase + i);
        }
        d.securityCouncilMembers = Utils.sortAddresses(d.securityCouncilMembers);

        d.guardiansMembers = new address[](8);
        for (uint256 i = 0; i < 8; ++i) {
            d.guardiansMembers[i] = _deploySafe(safeOwner, saltBase + 100 + i);
        }
        d.guardiansMembers = Utils.sortAddresses(d.guardiansMembers);

        d.zkFoundation = _deploySafe(safeOwner, saltBase + 200);
    }

    /// @dev Deploys the handler (impl + transparent proxy) and the governance bodies, wires them,
    ///      and hands the ProxyAdmin to the handler proxy (self-governed upgrades).
    function _deployHandlerStack(Ecosystem memory e, Deployed memory d, address deployer) internal {
        TestnetProtocolUpgradeHandler impl = new TestnetProtocolUpgradeHandler(
            vm.envAddress("L2_PROTOCOL_GOVERNOR"),
            e.zksyncEra,
            e.ctm,
            e.bridgeHub,
            e.l1Nullifier,
            e.l1AssetRouter,
            e.l1Ntv,
            e.cah
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), deployer, "");
        ProtocolUpgradeHandler puh = ProtocolUpgradeHandler(payable(address(proxy)));

        Guardians guardians = new Guardians(puh, e.zksyncEra, d.guardiansMembers);
        SecurityCouncil securityCouncil = new SecurityCouncil(puh, d.securityCouncilMembers);
        EmergencyUpgradeBoard board =
            new EmergencyUpgradeBoard(puh, address(securityCouncil), address(guardians), d.zkFoundation);

        puh.initialize(address(securityCouncil), address(guardians), address(board));

        address proxyAdmin = address(uint160(uint256(vm.load(address(proxy), ADMIN_SLOT))));
        ProxyAdmin(proxyAdmin).transferOwnership(address(proxy));

        d.puh = address(puh);
        d.impl = address(impl);
        d.proxyAdmin = proxyAdmin;
        d.guardians = address(guardians);
        d.securityCouncil = address(securityCouncil);
        d.board = address(board);
    }

    function _report(Deployed memory d) internal {
        console2.log("ProtocolUpgradeHandler (proxy):", d.puh);
        console2.log("ProtocolUpgradeHandler impl:", d.impl);
        console2.log("ProtocolUpgradeHandler ProxyAdmin:", d.proxyAdmin);
        console2.log("SecurityCouncil:", d.securityCouncil);
        console2.log("Guardians:", d.guardians);
        console2.log("EmergencyUpgradeBoard:", d.board);
        console2.log("ZkFoundationSafe:", d.zkFoundation);
        console2.log("L2ProtocolGovernor(timelock):", vm.envAddress("L2_PROTOCOL_GOVERNOR"));

        string memory obj = "l1";
        vm.serializeAddress(obj, "protocolUpgradeHandler", d.puh);
        vm.serializeAddress(obj, "protocolUpgradeHandlerImpl", d.impl);
        vm.serializeAddress(obj, "protocolUpgradeHandlerProxyAdmin", d.proxyAdmin);
        vm.serializeAddress(obj, "securityCouncil", d.securityCouncil);
        vm.serializeAddress(obj, "guardians", d.guardians);
        vm.serializeAddress(obj, "emergencyUpgradeBoard", d.board);
        vm.serializeAddress(obj, "zkFoundationSafe", d.zkFoundation);
        vm.serializeAddress(obj, "l2ProtocolGovernor", vm.envAddress("L2_PROTOCOL_GOVERNOR"));
        vm.serializeAddress(obj, "securityCouncilMembers", d.securityCouncilMembers);
        string memory json = vm.serializeAddress(obj, "guardiansMembers", d.guardiansMembers);
        vm.writeJson(json, vm.envString("L1_OUT"));
    }
}
