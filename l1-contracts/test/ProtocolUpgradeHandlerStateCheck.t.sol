// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {
  ProtocolUpgradeHandlerStateCheck,
  IProtocolUpgradeHandlerRoles
} from "../src/ProtocolUpgradeHandlerStateCheck.sol";

contract ProtocolUpgradeHandlerRolesMock is IProtocolUpgradeHandlerRoles {
  address public securityCouncil;
  address public guardians;
  address public emergencyUpgradeBoard;

  constructor(address _securityCouncil, address _guardians, address _emergencyUpgradeBoard) {
    securityCouncil = _securityCouncil;
    guardians = _guardians;
    emergencyUpgradeBoard = _emergencyUpgradeBoard;
  }
}

contract TestProtocolUpgradeHandlerStateCheck is Test {
  address securityCouncil = makeAddr("securityCouncil");
  address guardians = makeAddr("guardians");
  address emergencyUpgradeBoard = makeAddr("emergencyUpgradeBoard");

  ProtocolUpgradeHandlerStateCheck stateCheck = new ProtocolUpgradeHandlerStateCheck();
  ProtocolUpgradeHandlerRolesMock handler =
    new ProtocolUpgradeHandlerRolesMock(securityCouncil, guardians, emergencyUpgradeBoard);

  function test_PassesWhenRolesMatch() public view {
    stateCheck.checkRoles(handler, securityCouncil, guardians, emergencyUpgradeBoard);
  }

  function testFuzz_RevertWhen_SecurityCouncilDiffers(address _expected) public {
    vm.assume(_expected != securityCouncil);
    vm.expectRevert("Unexpected Security Council");
    stateCheck.checkRoles(handler, _expected, guardians, emergencyUpgradeBoard);
  }

  function testFuzz_RevertWhen_GuardiansDiffer(address _expected) public {
    vm.assume(_expected != guardians);
    vm.expectRevert("Unexpected guardians");
    stateCheck.checkRoles(handler, securityCouncil, _expected, emergencyUpgradeBoard);
  }

  function testFuzz_RevertWhen_EmergencyUpgradeBoardDiffers(address _expected) public {
    vm.assume(_expected != emergencyUpgradeBoard);
    vm.expectRevert("Unexpected Emergency Upgrade Board");
    stateCheck.checkRoles(handler, securityCouncil, guardians, _expected);
  }
}
