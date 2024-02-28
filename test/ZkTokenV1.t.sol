// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";

contract ZkTokenV1Test is Test {
  ZkTokenV1 token;
  address proxyOwner = makeAddr("Proxy Owner");
  address admin = makeAddr("Admin");

  // Placed here for convenience in tests. Must match the constants in the implementation.
  bytes32 public DEFAULT_ADMIN_ROLE = 0x00;
  bytes32 public MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 public BURNER_ROLE = keccak256("BURNER_ROLE");
  bytes32 public MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
  bytes32 public BURNER_ADMIN_ROLE = keccak256("BURNER_ADMIN_ROLE");

  function setUp() public {
    address _proxy =
      Upgrades.deployTransparentProxy("ZkTokenV1.sol", proxyOwner, abi.encodeCall(ZkTokenV1.initialize, (admin)));

    token = ZkTokenV1(_proxy);
  }
}

contract Initialize is ZkTokenV1Test {
  function test_InitializesTheTokenWithTheCorrectConfigurationWhenDeployedViaUpgrades() public {
    assertEq(token.symbol(), "ZK");
    assertEq(token.name(), "zkSync");

    // The admin has all three administrative roles after initialization
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, admin));
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, admin));

    // The administrative roles have the proper association with each role
    assertEq(token.getRoleAdmin(MINTER_ROLE), MINTER_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ROLE), BURNER_ADMIN_ROLE);

    // The administrative role of the administrative roles are the default admin
    assertEq(token.getRoleAdmin(MINTER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(token.getRoleAdmin(BURNER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);

    // The default administrative role self administers
    assertEq(token.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
  }

  function testFuzz_InitializesTheTokenWithTheCorrectConfigurationWhenCalledDirectly(address _admin) public {
    ZkTokenV1 _token = new ZkTokenV1();
    _token.initialize(_admin);

    // Same assertions as upgradeable deploy test
    assertEq(_token.symbol(), "ZK");
    assertEq(_token.name(), "zkSync");
    assertTrue(_token.hasRole(DEFAULT_ADMIN_ROLE, _admin));
    assertTrue(_token.hasRole(MINTER_ADMIN_ROLE, _admin));
    assertTrue(_token.hasRole(BURNER_ADMIN_ROLE, _admin));
    assertEq(_token.getRoleAdmin(MINTER_ROLE), MINTER_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(BURNER_ROLE), BURNER_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(MINTER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(BURNER_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
    assertEq(_token.getRoleAdmin(DEFAULT_ADMIN_ROLE), DEFAULT_ADMIN_ROLE);
  }

  function testFuzz_InitializesTheTokenSuchThatTheAdminRolesCanGrantTheRoleToOthers(address _newAdmin) public {
    vm.assume(_newAdmin != admin);

    // The default admin can add another default admin
    vm.prank(admin);
    token.grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, _newAdmin));

    // The new default admin can add other minter/burner admins
    vm.prank(_newAdmin);
    token.grantRole(MINTER_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, _newAdmin));
    vm.prank(_newAdmin);
    token.grantRole(BURNER_ADMIN_ROLE, _newAdmin);
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, _newAdmin));

    // The new default admin can revoke the default role from the original admin
    vm.prank(_newAdmin);
    token.revokeRole(DEFAULT_ADMIN_ROLE, admin);
    assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
  }
}
