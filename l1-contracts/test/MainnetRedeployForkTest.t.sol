// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, stdStorage, StdStorage, Vm} from "forge-std/Test.sol";

import {Callee} from "./utils/Callee.t.sol";
import {EmptyContract} from "./utils/EmptyContract.t.sol";
import {StateTransitionManagerMock} from "./mocks/StateTransitionManagerMock.t.sol";

import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "../../src/interfaces/IZKsyncEra.sol";
import {IStateTransitionManager} from "../../src/interfaces/IStateTransitionManager.sol";
import {IPausable} from "../../src/interfaces/IPausable.sol";

import {ProtocolUpgradeHandler} from "../../src/ProtocolUpgradeHandler.sol";


import {MainnetRedeploy} from "../scripts/MainnetRedeploy.s.sol";

import {DeployedContracts} from "../scripts/Redeploy.s.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";


// This test is focused to ensure that the new Proxy-based setup works correctly
contract MainnetRedeployForkTest is Test {
    using stdStorage for StdStorage;

    MainnetRedeploy script;
    DeployedContracts addresses;

    modifier onlyMainnet {
        if (block.chainid == 1) {
            _;
        } else {
            return;
        }
    }

    function setUp() external onlyMainnet {
        if (block.chainid != 1) {
            return;
        }

        Vm.Wallet memory deployerWallet = vm.createWallet("deployerWalelt");

        vm.setEnv("PRIVATE_KEY", vm.toString(deployerWallet.privateKey));
        vm.setEnv("L2_PROTOCOL_GOVERNOR", vm.toString(address(uint160(1))));

        MainnetRedeploy script = new MainnetRedeploy();
        script.run();

        addresses = script.getDeployedAddresses();
    }

    function emergencyUpgradeCall(address _to, bytes memory _data) internal {
        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](1);
        calls[0] = IProtocolUpgradeHandler.Call({
            target: _to,
            value: 0,
            data: _data
        });

        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            executor: addresses.emergencyUpgradeBoard,
            salt: bytes32(0)
        });

        vm.broadcast(addresses.emergencyUpgradeBoard);
        ProtocolUpgradeHandler(payable(addresses.protocolUpgradeHandlerProxy)).executeEmergencyUpgrade(proposal);
    }

    // Tests that the new ProtocolUpgradeHandler can upgrade itself
    function test_MainnetForkProxyUpgrade() external onlyMainnet {
        address proxyAdmin = address(uint160(uint256(vm.load(addresses.protocolUpgradeHandlerProxy, bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))));

        // We upgrade to an incorrect address (guradians), we just test that we can upgrade to a different impl.
        emergencyUpgradeCall(proxyAdmin, abi.encodeCall(ProxyAdmin.upgradeAndCall, (ITransparentUpgradeableProxy(addresses.protocolUpgradeHandlerProxy), addresses.guardians, hex"")));
    }

    // Ensures that the new ProtocolUpgradeHandler can call itself
    function test_MainnetForkSelfCall() external onlyMainnet {
        emergencyUpgradeCall(addresses.protocolUpgradeHandlerProxy, abi.encodeCall(ProtocolUpgradeHandler.updateSecurityCouncil, (address(uint160(1)))));
    }
}
