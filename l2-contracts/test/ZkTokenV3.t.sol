// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkTokenV3} from "src/ZkTokenV3.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract ZkTokenV3Test is Test {
  ZkTokenV3 tokenV3;
  address admin = makeAddr("Admin");
  uint256 constant INITIAL_MINT_AMOUNT = 1_000_000_000e18;
  uint256 constant MAX_SUPPLY = 21_000_000_000e18;
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

  function setUp() public virtual {
    tokenV3 = new ZkTokenV3();
    tokenV3.initialize(admin, admin, INITIAL_MINT_AMOUNT);
    tokenV3.initializeV2();
  }

  function _mint(address _to, uint256 _amount) internal {
    vm.startPrank(admin);
    tokenV3.grantRole(MINTER_ROLE, admin);
    tokenV3.mint(_to, _amount);
    vm.stopPrank();
  }

  function _formatAccessControlError(address account, bytes32 role) internal pure returns (bytes memory) {
    return bytes(
      string.concat(
        "AccessControl: account ",
        Strings.toHexString(uint160(account), 20),
        " is missing role ",
        Strings.toHexString(uint256(role), 32)
      )
    );
  }
}

contract Initialize is ZkTokenV3Test {
  function calculateDomainSeparator(address _token) public view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes("ZKsync")),
        keccak256(bytes("1")),
        block.chainid,
        _token
      )
    );
  }

  function test_InitializesTheTokenWithTheCorrectConfigurationWhenDeployed() public {
    assertEq(tokenV3.symbol(), "ZK");
    assertEq(tokenV3.name(), "ZKsync");
    assertEq(tokenV3.maxSupply(), 21_000_000_000e18);
    assertEq(tokenV3.DOMAIN_SEPARATOR(), calculateDomainSeparator(address(tokenV3)));
    assertEq(tokenV3.totalSupply(), INITIAL_MINT_AMOUNT);
    assertEq(tokenV3.balanceOf(admin), INITIAL_MINT_AMOUNT);
  }

  function testFuzz_RevertIf_TheInitializerV3IsCalledTwice() public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3.initializeV2();
  }
}

contract MaxSupply is ZkTokenV3Test {
  function test_ReturnsTheCorrectMaxSupply() public {
    assertEq(tokenV3.maxSupply(), MAX_SUPPLY);
  }
}

contract Burn is ZkTokenV3Test {
  function testFuzz_CallerCanBurnTokens(uint256 _initialBalance, uint256 _burnAmount, address _caller) public {
    vm.assume(_caller != address(0) && _caller != admin);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    _mint(_caller, _initialBalance);
    uint256 _initialSupply = tokenV3.totalSupply();

    vm.prank(_caller);
    tokenV3.burn(_burnAmount);

    assertEq(tokenV3.balanceOf(_caller), _initialBalance - _burnAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply - _burnAmount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveEnoughBalance(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller
  ) public {
    vm.assume(_caller != address(0));
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT - 1);
    _burnAmount = bound(_burnAmount, _initialBalance + 1, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _mint(_caller, _initialBalance);

    vm.expectRevert("ERC20: burn amount exceeds balance");
    vm.prank(_caller);
    tokenV3.burn(_burnAmount);
  }
}

contract BurnFrom is ZkTokenV3Test {
  bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

  function _grantBurnerRole(address _to) internal {
    vm.prank(admin);
    tokenV3.grantRole(BURNER_ROLE, _to);
  }

  function testFuzz_CallerWithBurnerRoleCanBurnTokensFromAnotherAddress(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != admin);
    vm.assume(_from != address(0) && _from != admin);
    _grantBurnerRole(_caller);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    _mint(_from, _initialBalance);
    uint256 _initialSupply = tokenV3.totalSupply();

    vm.prank(_caller);
    tokenV3.burnFrom(_from, _burnAmount);

    assertEq(tokenV3.balanceOf(_from), _initialBalance - _burnAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply - _burnAmount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveBurnerRole(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != admin);
    vm.assume(_from != address(0) && _from != admin);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    _mint(_from, _initialBalance);

    vm.expectRevert(_formatAccessControlError(_caller, BURNER_ROLE));
    vm.prank(_caller);
    tokenV3.burnFrom(_from, _burnAmount);
  }
}
