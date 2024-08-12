// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "forge-std/Script.sol";
import {Vm, console2} from "forge-std/Test.sol";

import "./Utils.sol";
import "./ICREATE3Factory.sol";

import "../src/SecurityCouncil.sol";
import "../src/Guardians.sol";
import "../src/ProtocolUpgradeHandler.sol";
import "./interfaces/IL1Messenger.sol";

contract PrepareUpgradeCalldata is Script {
    IL1Messenger constant L1_MESSENGER_CONTRACT = IL1Messenger(address(0x8008));
    ProtocolUpgradeHandler constant PROTOCOL_UPGRADE_HANDLER = ProtocolUpgradeHandler(address(0x9B956d242e6806044877C7C1B530D475E371d544));

    function prepareCalldata(IProtocolUpgradeHandler.UpgradeProposal calldata _proposal) public returns(address to, bytes memory data) {
        to = address(L1_MESSENGER_CONTRACT);
        data = abi.encode(_proposal);
    }

    function startUpgrade(
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _proof,
        UpgradeProposal calldata _proposal
    ) external {
        vm.startBroadcast();
        PROTOCOL_UPGRADE_HANDLER.startUpgrade(_l2BatchNumber, _l2MessageIndex, _l2TxNumberInBatch, _proof, _proposal);
        vm.stopBroadcast();
    }
}
