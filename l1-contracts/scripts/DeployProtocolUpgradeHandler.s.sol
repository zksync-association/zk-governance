// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol";
import {IChainTypeManager} from "../src/interfaces/IChainTypeManager.sol";
import {IBridgeHub} from "../src/interfaces/IBridgeHub.sol";
import {IPausable} from "../src/interfaces/IPausable.sol";
import {IChainAssetHandler} from "../src/interfaces/IChainAssetHandler.sol";

contract DeployProtocolUpgradeHandler is Script {
    function bytesToAddress(bytes memory data) internal pure returns (address addr) {
        require(data.length >= 20, "Invalid address data");
        assembly {
            addr := mload(add(data, 20))
        }
    }

    function deployViaCreate2(bytes memory _bytecode, bytes32 _salt, address _factory) internal returns (address) {
        if (_bytecode.length == 0) {
            revert("Bytecode is not set");
        }
        address contractAddress = vm.computeCreate2Address(_salt, keccak256(_bytecode), _factory);
        if (contractAddress.code.length != 0) {
            return contractAddress;
        }

        vm.broadcast();
        (bool success, bytes memory data) = _factory.call(abi.encodePacked(_salt, _bytecode));
        contractAddress = bytesToAddress(data);

        if (!success || contractAddress == address(0) || contractAddress.code.length == 0) {
            revert("Failed to deploy contract via create2");
        }

        return contractAddress;
    }

    function run() external {
        address prevHandlerAddr = vm.envAddress("PREV_PROTOCOL_UPGRADE_HANDLER");
        address chainAssetHandlerAddr = vm.envAddress("CHAIN_ASSET_HANDLER");
        address create2FactoryAddr = vm.envAddress("CREATE2_FACTORY");
        bytes32 salt = vm.envBytes32("CREATE2_SALT");
        uint256 chainId = vm.envUint("ERA_CHAIN_ID");

        ProtocolUpgradeHandler prev = ProtocolUpgradeHandler(payable(prevHandlerAddr));

        bytes memory bytecode = abi.encodePacked(
            type(ProtocolUpgradeHandler).creationCode,
            abi.encode(
                prev.L2_PROTOCOL_GOVERNOR(),
                prev.CHAIN_TYPE_MANAGER(),
                prev.BRIDGE_HUB(),
                prev.L1_NULLIFIER(),
                prev.L1_ASSET_ROUTER(),
                prev.L1_NATIVE_TOKEN_VAULT(),
                IChainAssetHandler(chainAssetHandlerAddr),
                chainId  //ToDo after the next redeployment, update to prev.ERA_CHAIN_ID()
            )
        );

        address deployed = deployViaCreate2(bytecode, salt, create2FactoryAddr);
        console2.log("ProtocolUpgradeHandler deployed at:", deployed);
    }
}
