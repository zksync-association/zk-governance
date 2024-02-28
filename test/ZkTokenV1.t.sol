// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

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

  // As defined internally in ERC20Votes
  uint256 MAX_MINT_SUPPLY = type(uint208).max;

  function setUp() public {
    address _proxy =
      Upgrades.deployTransparentProxy("ZkTokenV1.sol", proxyOwner, abi.encodeCall(ZkTokenV1.initialize, (admin)));
    vm.label(_proxy, "Proxy");

    token = ZkTokenV1(_proxy);

    // TODO: if the fuzzer chooses the ProxyAdmin contract as an address that will call into the contract, it will
    // end up throwing a ProxyDeniedAdminAccess error. How do we get access to the address of the deployed ProxyAdmin,
    // such that we can write an _assumeNotProxyAdmin function to prevent selection by the fuzzer.
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

contract Mint is ZkTokenV1Test {
  function testFuzz_AllowsAnAccountWithTheMinterRoleToMintTokens(address _minter, address _receiver, uint256 _amount)
    public
  {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    token.mint(_receiver, _amount);

    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_AllowsMultipleAccountsWithTheMinterRoleToMintTokens(
    address _minter1,
    address _receiver1,
    uint256 _amount1,
    address _minter2,
    address _receiver2,
    uint256 _amount2
  ) public {
    vm.assume(_receiver1 != address(0) && _receiver2 != address(0) && _receiver1 != _receiver2);
    _amount1 = bound(_amount1, 0, MAX_MINT_SUPPLY / 2);
    _amount2 = bound(_amount2, 0, MAX_MINT_SUPPLY / 2);

    // grant minter role to multiple accounts
    vm.startPrank(admin);
    token.grantRole(MINTER_ROLE, _minter1);
    token.grantRole(MINTER_ROLE, _minter2);
    vm.stopPrank();

    // first minter mints some tokens
    vm.prank(_minter1);
    token.mint(_receiver1, _amount1);

    // second minter mints some tokens
    vm.prank(_minter2);
    token.mint(_receiver2, _amount2);

    assertEq(token.balanceOf(_receiver1), _amount1);
    assertEq(token.balanceOf(_receiver2), _amount2);
  }

  function testFuzz_RevertIf_AnAccountWithoutTheMinterRoleAttemptsToMint(
    address _notMinter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _notMinter, MINTER_ROLE)
    );
    vm.prank(_notMinter);
    token.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_AnAccountThatHasHadTheMinterRoleRevokedAttemptsToMint(
    address _formerMinter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 0, MAX_MINT_SUPPLY);

    // grant the account the minter role and exercise minting rights
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, _formerMinter);
    vm.prank(_formerMinter);
    token.mint(_receiver, _amount);

    // revoke the minter role from the account
    vm.prank(admin);
    token.revokeRole(MINTER_ROLE, _formerMinter);

    // attempting to mint should now cause the contract to revert
    vm.expectRevert(
      abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, _formerMinter, MINTER_ROLE)
    );
    vm.prank(_formerMinter);
    token.mint(_receiver, _amount);
  }
}
