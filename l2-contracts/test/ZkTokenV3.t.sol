// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkTokenV3} from "src/ZkTokenV3.sol";
import {ZkTokenV2} from "src/ZkTokenV2.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
  TransparentUpgradeableProxy,
  ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ZkTokenV3Test is Test {
  ZkTokenV3 tokenV3Implementation;
  ZkTokenV3 tokenV3Proxy;
  address admin = makeAddr("Admin");
  address proxyAdmin = makeAddr("Proxy Admin");
  address deployer = makeAddr("Deployer");
  address initMintReceiver = makeAddr("Init Mint Receiver");

  address constant ZK_TOKEN_GOVERNOR = 0xb83FF6501214ddF40C91C9565d095400f3F45746;
  address constant TOKEN_GOVERNOR_TIMELOCK = 0xe5d21A9179CA2E1F0F327d598D464CcF60d89c3d;
  address constant ZK_TOKEN_PROXY_ADDRESS = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  uint256 constant INITIAL_MINT_AMOUNT = 1_000_000_000e18;
  uint256 constant MAX_SUPPLY = 21_000_000_000e18;
  bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");
  bytes32 constant BURNER_ROLE = keccak256("BURNER_ROLE");
  address constant TOKEN_V3_PROXY_ADMIN_ADDRESS = 0x5c74C60466EFa384D53C7422534C1E242151d686;

  function setUp() public virtual {
    tokenV3Implementation = new ZkTokenV3();

    vm.startPrank(deployer);
    bytes memory _initData = abi.encodeCall(ZkTokenV1.initialize, (admin, initMintReceiver, INITIAL_MINT_AMOUNT));
    TransparentUpgradeableProxy _proxy =
      new TransparentUpgradeableProxy(address(tokenV3Implementation), proxyAdmin, _initData);
    vm.stopPrank();
    tokenV3Proxy = ZkTokenV3(payable(address(_proxy)));
    tokenV3Proxy.initializeV2();
  }

  function _mint(address _to, uint256 _amount) internal {
    vm.startPrank(admin);
    tokenV3Proxy.grantRole(tokenV3Implementation.MINTER_ROLE(), admin);
    tokenV3Proxy.mint(_to, _amount);
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
    assertEq(tokenV3Proxy.symbol(), "ZK");
    assertEq(tokenV3Proxy.name(), "ZKsync");
    assertEq(tokenV3Proxy.DOMAIN_SEPARATOR(), calculateDomainSeparator(address(tokenV3Proxy)));
    assertEq(tokenV3Proxy.totalSupply(), INITIAL_MINT_AMOUNT);
    assertEq(tokenV3Proxy.balanceOf(initMintReceiver), INITIAL_MINT_AMOUNT);
  }

  function testFuzz_RevertIf_TheInitializerIsCalledTwice(
    address _admin,
    address _initMintReceiver,
    uint256 _initialMintAmount
  ) public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3Implementation.initialize(_admin, _initMintReceiver, _initialMintAmount);
  }

  function testFuzz_RevertIf_TheInitializerV2IsCalledTwice() public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3Implementation.initializeV2();
  }

  function testFuzz_RevertIf_TheInitializerIsCalledTwiceOnTheProxy(
    address _admin,
    address _initMintReceiver,
    uint256 _initialMintAmount
  ) public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3Proxy.initialize(_admin, _initMintReceiver, _initialMintAmount);
  }

  function testFuzz_RevertIf_TheInitializerV2IsCalledTwiceOnTheProxy() public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3Proxy.initializeV2();
  }
}

contract Clock is ZkTokenV3Test {
  function test_ReturnsTheCorrectClock() public {
    assertEq(tokenV3Implementation.clock(), SafeCastUpgradeable.toUint48(block.timestamp));
  }
}

contract CLOCK_MODE is ZkTokenV3Test {
  function test_ReturnsTheCorrectClockMode() public {
    assertEq(tokenV3Implementation.CLOCK_MODE(), "mode=timestamp");
  }
}

contract Mint is ZkTokenV3Test {
  function testFuzz_RevertIf_CallerMintsOnTheImplementation(uint256 _mintAmount, address _caller) public {
    vm.expectRevert(_formatAccessControlError(_caller, MINTER_ROLE));
    vm.prank(_caller);
    tokenV3Implementation.mint(_caller, _mintAmount);
  }
}

contract Burn is ZkTokenV3Test {
  function testFuzz_RevertIf_CallerBurnsTokensOnTheImplementationWithoutBalance(uint256 _burnAmount, address _caller)
    public
  {
    vm.assume(_caller != address(0) && _caller != TOKEN_V3_PROXY_ADMIN_ADDRESS);
    _burnAmount = bound(_burnAmount, 1, MAX_SUPPLY);

    vm.expectRevert("ERC20: burn amount exceeds balance");
    vm.prank(_caller);
    tokenV3Implementation.burn(_burnAmount);
  }

  function testFuzz_CallerCanBurnTokens(uint256 _mintAmount, uint256 _burnAmount, address _caller) public {
    vm.assume(_caller != address(0) && _caller != TOKEN_V3_PROXY_ADMIN_ADDRESS);
    _mintAmount = bound(_mintAmount, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);
    _mint(_caller, _mintAmount);
    uint256 _initialBalance = tokenV3Proxy.balanceOf(_caller);
    uint256 _initialSupply = tokenV3Proxy.totalSupply();

    vm.prank(_caller);
    tokenV3Proxy.burn(_burnAmount);

    assertEq(tokenV3Proxy.balanceOf(_caller), _initialBalance - _burnAmount);
    assertEq(tokenV3Proxy.totalSupply(), _initialSupply - _burnAmount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveEnoughBalance(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller
  ) public {
    vm.assume(_caller != address(0) && _caller != initMintReceiver && _caller != TOKEN_V3_PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT - 1);
    _burnAmount = bound(_burnAmount, _initialBalance + 1, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _mint(_caller, _initialBalance);

    vm.expectRevert("ERC20: burn amount exceeds balance");
    vm.prank(_caller);
    tokenV3Proxy.burn(_burnAmount);
  }
}

contract BurnFrom is ZkTokenV3Test {
  function _grantBurnerRole(address _to) internal {
    vm.prank(admin);
    tokenV3Proxy.grantRole(BURNER_ROLE, _to);
  }

  function testFuzz_CallerWithBurnerRoleCanBurnTokensFromAnotherAddress(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != TOKEN_V3_PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != admin);
    uint256 _fromExistingBalance = tokenV3Proxy.balanceOf(_from);
    _grantBurnerRole(_caller);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    _mint(_from, _initialBalance);
    uint256 _initialSupply = tokenV3Proxy.totalSupply();

    vm.prank(_caller);
    tokenV3Proxy.burnFrom(_from, _burnAmount);

    assertEq(tokenV3Proxy.balanceOf(_from), _initialBalance - _burnAmount + _fromExistingBalance);
    assertEq(tokenV3Proxy.totalSupply(), _initialSupply - _burnAmount);
  }

  function testFuzz_RevertIf_CallerDoesNotHaveBurnerRole(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != TOKEN_V3_PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != admin);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - INITIAL_MINT_AMOUNT);
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    _mint(_from, _initialBalance);

    vm.expectRevert(_formatAccessControlError(_caller, BURNER_ROLE));
    vm.prank(_caller);
    tokenV3Proxy.burnFrom(_from, _burnAmount);
  }
}
