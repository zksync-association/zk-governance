// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ISafeSetup.sol";
import "./IGnosisSafeProxyFactory.sol";
import "./ICREATE3Factory.sol";

// import "../src/SecurityCouncil.sol";
// import "../src/Guardians.sol";
// import "../src/EmergencyUpgradeBoard.sol";
// import "../src/Multisig.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProtocolUpgradeHandler} from "../src/ProtocolUpgradeHandler.sol"; 
import {IProtocolUpgradeHandler} from "../src/interfaces/IProtocolUpgradeHandler.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IZKsyncEra} from "../src/interfaces/IZKsyncEra.sol";
import {AddressAliasHelper} from "./vendor/AddressAliasHelper.sol";

// import {TestnetProtocolUpgradeHandler} from "../src/TestnetProtocolUpgradeHandler.sol"; 

import {Redeploy} from "./Redeploy.s.sol";

interface Ownable2Step {
    function transferOwnership(address to) external;
    function acceptOwnership() external;
}

// Outputs calldata needed to migrate the ownership to contracts to the new protocol upgrade handler.
contract OwnershipMigration is Redeploy {

    function getProxyAdmin(address _proxyAddr) internal view returns (address proxyAdmin) {
        proxyAdmin = address(uint160(uint256(vm.load(_proxyAddr, bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))));
    }

    function getTransferProxyOwnershipCall(address _proxyAddr, address _newOwner) internal view returns (IProtocolUpgradeHandler.Call memory call) {
        // Proxy admin slot
        address proxyAdmin = address(uint160(uint256(vm.load(_proxyAddr, bytes32(0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103)))));

        call = IProtocolUpgradeHandler.Call({
            target: proxyAdmin,
            data: abi.encodeCall(Ownable2Step.transferOwnership, (_newOwner)),
            value: 0
        });
    }

    function getTransferOwnershipCall(address _addr, address _newOwner) internal view returns (IProtocolUpgradeHandler.Call memory call) {
        call = IProtocolUpgradeHandler.Call({
            target: _addr,
            data: abi.encodeCall(Ownable2Step.transferOwnership, (_newOwner)),
            value: 0
        });
    }

    function getAcceptOwnershipCall(address _addr) internal view returns (IProtocolUpgradeHandler.Call memory call) {
        call = IProtocolUpgradeHandler.Call({
            target: _addr,
            data: abi.encodeCall(Ownable2Step.acceptOwnership, ()),
            value: 0
        });
    }

    /// @notice The maximal L1 gas price that the L1->L2 should be used with.
    uint256 constant MAX_L1_GAS_PRICE = 50 gwei;
    /// @notice The gas limit of the L1->L2 transaction
    uint256 constant L2_GAS_LIMIT = 10_000_000;
    /// @notice The L2 gas per pubdata byte limit
    uint256 constant L2_GAS_PER_PUBDATA_BYTE_LIMIT = 800;

    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0);
    
    function getL1ToL2Tx(
        address _zksyncEra,
        address _contractL2, 
        bytes memory _l2Data
    ) internal view returns (IProtocolUpgradeHandler.Call memory call) {
        uint256 baseCost = IZKsyncEra(_zksyncEra).l2TransactionBaseCost(
            MAX_L1_GAS_PRICE,
            L2_GAS_LIMIT,
            L2_GAS_PER_PUBDATA_BYTE_LIMIT
        );

        call = IProtocolUpgradeHandler.Call({
            target: _zksyncEra,
            value: baseCost,
            data: abi.encodeCall(
                IZKsyncEra.requestL2Transaction,
                (
                    _contractL2,
                    0,
                    _l2Data,
                    L2_GAS_LIMIT,
                    L2_GAS_PER_PUBDATA_BYTE_LIMIT,
                    new bytes[](0),
                    msg.sender
                )
            )
        });
    } 


    function runMoveOwnership(
        address _zkTokenAddr,
        ProtocolUpgradeHandler _currentProtocolUpgradeHandler,
        ProtocolUpgradeHandler _newProtocolUpgradeHandler
    ) external {
        CurrentSystemParams memory systemParams = extractDataFromProtocolUpgradeHandler(_currentProtocolUpgradeHandler);

        bytes memory transferOwnershipData;

        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](7);
        calls[0] = getTransferProxyOwnershipCall(systemParams.bridgehub, address(_newProtocolUpgradeHandler));
        calls[1] = getTransferOwnershipCall(systemParams.bridgehub, address(_newProtocolUpgradeHandler));

        address bridgehubProxyAdmin = getProxyAdmin(systemParams.bridgehub);

        require(getProxyAdmin(systemParams.stateTransitionManager) == bridgehubProxyAdmin);
        calls[2] = getTransferOwnershipCall(systemParams.stateTransitionManager, address(_newProtocolUpgradeHandler));


        require(getProxyAdmin(systemParams.l1Erc20Bridge) == bridgehubProxyAdmin);

        require(getProxyAdmin(systemParams.sharedBridge) == bridgehubProxyAdmin);
        calls[3] = getTransferOwnershipCall(systemParams.sharedBridge, address(_newProtocolUpgradeHandler));
 
        calls[4] = getTransferOwnershipCall(systemParams.validatorTimelock, address(_newProtocolUpgradeHandler));

        calls[5] = getL1ToL2Tx(
            systemParams.zksyncEra,
            _zkTokenAddr,
            abi.encodeCall(AccessControlUpgradeable.grantRole, (DEFAULT_ADMIN_ROLE, AddressAliasHelper.applyL1ToL2Alias(address(_newProtocolUpgradeHandler))))
        );
        calls[6] = getL1ToL2Tx(
            systemParams.zksyncEra,
            _zkTokenAddr,
            abi.encodeCall(AccessControlUpgradeable.renounceRole, (DEFAULT_ADMIN_ROLE, AddressAliasHelper.applyL1ToL2Alias(address(_currentProtocolUpgradeHandler))))
        );

        // We now compile the data needed to transfer ownership to the new PUH
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            executor: address(0),
            salt: bytes32(0)
        });

        console2.logBytes(abi.encode(proposal));
    }

    function runAcceptOwnership(
        ProtocolUpgradeHandler _currentProtocolUpgradeHandler,
        ProtocolUpgradeHandler _newProtocolUpgradeHandler
    ) external {
        CurrentSystemParams memory systemParams = extractDataFromProtocolUpgradeHandler(_currentProtocolUpgradeHandler);

        bytes memory transferOwnershipData;

        IProtocolUpgradeHandler.Call[] memory calls = new IProtocolUpgradeHandler.Call[](5);
        calls[0] = getAcceptOwnershipCall(systemParams.bridgehub);
        calls[1] = getAcceptOwnershipCall(systemParams.stateTransitionManager);
        calls[2] = getAcceptOwnershipCall(systemParams.sharedBridge);
        calls[3] = getAcceptOwnershipCall(systemParams.validatorTimelock);

        // We now compile the data needed to transfer ownership to the new PUH
        IProtocolUpgradeHandler.UpgradeProposal memory proposal = IProtocolUpgradeHandler.UpgradeProposal({
            calls: calls,
            // This one is expected to be an emergency upgrade.
            executor: address(_newProtocolUpgradeHandler),
            salt: bytes32(0)
        });

        console2.logBytes(abi.encode(proposal));
    }
}
