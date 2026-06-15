// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "../src/interfaces/IZKsyncEra.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";
import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

interface IPUH {
    function startUpgrade(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _proof,
        IProtocolUpgradeHandler.UpgradeProposal calldata _proposal
    ) external;
    function upgradeState(bytes32) external view returns (uint8);
    function ZKSYNC_ERA() external view returns (address);
    function L2_PROTOCOL_GOVERNOR() external view returns (address);
}

/// @notice Forks Sepolia and verifies that the L2->L1 upgrade message produced by cli-vote (i.e.
/// `abi.encode(UpgradeProposal)` sent through the L2 L1Messenger by the L2 timelock) is accepted
/// by the *deployed testnet* ProtocolUpgradeHandler's `startUpgrade`.
///
/// The L2 batch proof cannot be produced until the batch is sealed & executed on L1 (hours), so we
/// mock the diamond's `proveL2MessageInclusion` to return true — this isolates and validates the
/// part under test: message *format* compatibility and the upgrade-id derivation. The message
/// sender wiring is checked separately by asserting the handler's L2_PROTOCOL_GOVERNOR equals the
/// L2 timelock that emits the message.
///
/// Env:
///   SEPOLIA_RPC      L1 fork RPC
///   PUH_ADDRESS      deployed TestnetProtocolUpgradeHandler (proxy)
///   MESSAGE_HEX      the exact L2->L1 message bytes emitted by the executed proposal
///   EXPECTED_SENDER  the L2 timelock address (== handler's L2_PROTOCOL_GOVERNOR)
contract L2MessageCompatForkTest is Test {
    function test_startUpgradeAcceptsCliVoteMessage() external {
        string memory rpc = vm.envString("SEPOLIA_RPC");
        vm.createSelectFork(rpc);

        bytes memory message = vm.envBytes("MESSAGE_HEX");
        address expectedSender = vm.envAddress("EXPECTED_SENDER");
        // Use the real deployed handler if provided, else deploy an identical TestnetProtocolUpgradeHandler
        // on the fork wired to the same L2 timelock (lets us validate compatibility without waiting for
        // the real L1 deploy / gas window).
        IPUH puh = _resolvePuh(expectedSender);

        // The handler must treat the L2 timelock as the authorized message sender.
        assertEq(puh.L2_PROTOCOL_GOVERNOR(), expectedSender, "handler L2 governor != L2 timelock");

        // Decode the message exactly as `startUpgrade` will re-encode it.
        IProtocolUpgradeHandler.UpgradeProposal memory proposal =
            abi.decode(message, (IProtocolUpgradeHandler.UpgradeProposal));

        // Round-trip: re-encoding the decoded proposal must reproduce the original message bytes,
        // which is precisely what the handler hashes into the upgrade id.
        bytes memory reencoded = abi.encode(proposal);
        assertEq(keccak256(reencoded), keccak256(message), "re-encoded proposal != emitted message");
        bytes32 id = keccak256(message);

        // Mock the L2 message-inclusion proof on the chain's diamond so the proof check passes.
        address era = puh.ZKSYNC_ERA();
        vm.mockCall(era, abi.encodeWithSelector(IZKsyncEra.proveL2MessageInclusion.selector), abi.encode(true));

        // Sanity: upgrade does not exist yet.
        assertEq(puh.upgradeState(id), uint8(0), "upgrade should not exist yet");

        bytes32[] memory proof = new bytes32[](0);
        puh.startUpgrade(1, 0, 0, proof, proposal);

        // Testnet handler has 0-length legal veto, so the upgrade is immediately Waiting (state 2).
        uint8 state = puh.upgradeState(id);
        assertEq(state, uint8(IProtocolUpgradeHandler.UpgradeState.Waiting), "upgrade not Waiting after startUpgrade");
        console2.log("startUpgrade accepted; upgrade id:");
        console2.logBytes32(id);
        console2.log("upgrade state (2=Waiting):", state);
    }

    function _envOr(string memory key, address dflt) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return dflt;
        }
    }

    /// Returns the deployed handler (PUH_ADDRESS) or deploys an identical one on the fork.
    function _resolvePuh(address l2Governor) internal returns (IPUH) {
        try vm.envAddress("PUH_ADDRESS") returns (address a) {
            return IPUH(a);
        } catch {}

        // chain-301 Sepolia ecosystem defaults (same as DeployL1Governance.s.sol)
        TestnetProtocolUpgradeHandler impl = new TestnetProtocolUpgradeHandler(
            l2Governor,
            IZKsyncEra(_envOr("ZKSYNC_ERA", 0xD3bc4353957bc0F138318384aa207C708A9455C4)),
            IChainTypeManager(_envOr("CHAIN_TYPE_MANAGER", 0x3Cc81628a14C824057a97C1B4Ab17758E5D18864)),
            IBridgeHub(_envOr("BRIDGE_HUB", 0xc4FD2580C3487bba18D63f50301020132342fdbD)),
            IPausable(_envOr("L1_NULLIFIER", 0x9e24E2c23933d30eF2DEB70A0D977Fb1Ca20AbEa)),
            IPausable(_envOr("L1_ASSET_ROUTER", 0xB5d9C3F41E434b91295BD7962db5c873cEcCE2be)),
            IPausable(_envOr("L1_NATIVE_TOKEN_VAULT", 0xF8d4A5195737043f45F998539D5C62Eee02E3426)),
            IChainAssetHandler(_envOr("CHAIN_ASSET_HANDLER", 0xDfA2193b161d7bd45FC81b4E80225eebDc3CF96C))
        );
        // Minimal wiring: startUpgrade only reads L2_PROTOCOL_GOVERNOR + emergencyUpgradeBoard.
        bytes memory init = abi.encodeCall(ProtocolUpgradeHandler.initialize, (address(0x5C), address(0x6D), address(0x7B)));
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(impl), address(this), init);
        return IPUH(address(proxy));
    }
}
