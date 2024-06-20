// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.t.sol";
import {SecurityCouncil} from "../../src/SecurityCouncil.sol";
import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract TestSecurityCouncil is Test {
    IProtocolUpgradeHandler protocolUpgradeHandler = IProtocolUpgradeHandler(makeAddr("protocolUpgradeHandler"));
    SecurityCouncil securityCouncil;
    Vm.Wallet[] wallets;
    address[] internal members;

    constructor() {
        Vm.Wallet[] memory wallets_ = new Vm.Wallet[](12);
        for (uint256 i = 0; i < 12; i++) {
            wallets_[i] = vm.createWallet(string(abi.encodePacked("Account: ", i)));
        }
        wallets_ = Utils.sortWalletsByAddress(wallets_);

        for (uint256 i = 0; i < 12; i++) {
            wallets.push(wallets_[i]);
            members.push(wallets_[i].addr);
        }

        securityCouncil = new SecurityCouncil(protocolUpgradeHandler, members);
    }

    function test_RevertWhen_NotTwelveMembers() public {
        address[] memory members = new address[](10);

        for (uint256 i = 0; i < 10; i++) {
            members[i] = address(uint160(i + 1));
        }

        vm.expectRevert("SecurityCouncil requires exactly 12 members");
        new SecurityCouncil(protocolUpgradeHandler, members);
    }

    function test_RevertWhen_softFreezeSignatureExpired() public {
        vm.expectRevert("Signature expired");
        securityCouncil.softFreeze(block.timestamp - 1, members, new bytes[](0));
    }

    function test_RevertWhen_hardFreezeSignatureExpired() public {
        vm.expectRevert("Signature expired");
        securityCouncil.hardFreeze(block.timestamp - 1, members, new bytes[](0));
    }

    function test_RevertWhen_unfreezeSignatureExpired() public {
        vm.expectRevert("Signature expired");
        securityCouncil.unfreeze(block.timestamp - 1, members, new bytes[](0));
    }

    function test_RevertWhen_setSoftFreezeThresholdSignatureExpired() public {
        vm.expectRevert("Signature expired");
        securityCouncil.setSoftFreezeThreshold(1, block.timestamp - 1, members, new bytes[](0));
    }
}
