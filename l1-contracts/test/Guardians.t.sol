// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Utils} from "./utils/Utils.t.sol";
import {Guardians} from "../../src/Guardians.sol";
import {IProtocolUpgradeHandler} from "../../src/interfaces/IProtocolUpgradeHandler.sol";
import {IZKsyncEra} from "../../src/interfaces/IZKsyncEra.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract TestGuardians is Test {
    IProtocolUpgradeHandler protocolUpgradeHandler = IProtocolUpgradeHandler(makeAddr("protocolUpgradeHandler"));
    IZKsyncEra zksyncAddress = IZKsyncEra(makeAddr("zksyncAddress"));
    Guardians guardians;
    Vm.Wallet[] wallets;
    address[] internal members;

    constructor() {
        Vm.Wallet[] memory wallets_ = new Vm.Wallet[](8);
        for (uint256 i = 0; i < 8; i++) {
            wallets_[i] = vm.createWallet(string(abi.encodePacked("Account: ", i)));
        }
        wallets_ = Utils.sortWalletsByAddress(wallets_);

        for (uint256 i = 0; i < 8; i++) {
            wallets.push(wallets_[i]);
            members.push(wallets_[i].addr);
        }

        guardians = new Guardians(protocolUpgradeHandler, zksyncAddress, members);
    }

    function test_RevertWhen_NotEightMembers() public {
        address[] memory members = new address[](7);

        for (uint256 i = 0; i < 7; i++) {
            members[i] = address(uint160(i + 1));
        }

        vm.expectRevert("Guardians requires exactly 8 members");
        new Guardians(protocolUpgradeHandler, zksyncAddress, members);
    }
}
