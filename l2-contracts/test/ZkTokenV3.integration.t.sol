// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenV3} from "src/ZkTokenV3.sol";
import {ZkTokenV2} from "src/ZkTokenV2.sol";
import {ZkTokenV1} from "src/ZkTokenV1.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ZkTokenV3Test} from "./ZkTokenV3.t.sol";
import {
  TransparentUpgradeableProxy,
  ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ZkTokenV3ForkTest is ZkTokenV3Test {
  ZkTokenV3 tokenV3;
  uint256 constant FORK_BLOCK_NUMBER = 62_000_000;
  address constant PROXY_ADMIN_ADDRESS = 0xdB1E46B448e68a5E35CB693a99D59f784aD115CC;
  address constant ADMIN_ADDRESS = 0xF41EcA3047B37dc7d88849de4a4dc07937Ad6bc4;

  function setUp() public virtual override {
    super.setUp();
    vm.createSelectFork(vm.envString("ZK_RPC_URL"), FORK_BLOCK_NUMBER);
    _upgradeProxyImplementationToV3(tokenV3Implementation);
    tokenV3 = ZkTokenV3(payable(ZK_TOKEN_PROXY_ADDRESS));
    vm.startPrank(ADMIN_ADDRESS);
    tokenV3.grantRole(tokenV3.BURNER_ADMIN_ROLE(), ADMIN_ADDRESS);
    vm.stopPrank();
  }

  function _upgradeProxyImplementationToV3(ZkTokenV3 _tokenV3Implementation) internal {
    ProxyAdmin _proxy = ProxyAdmin(payable(PROXY_ADMIN_ADDRESS));
    vm.prank(_proxy.owner());
    _proxy.upgrade(ITransparentUpgradeableProxy(ZK_TOKEN_PROXY_ADDRESS), address(_tokenV3Implementation));
  }

  function _grantBurnerRole(address _to) internal {
    vm.startPrank(ADMIN_ADDRESS);
    tokenV3.grantRole(tokenV3.BURNER_ROLE(), _to);
    vm.stopPrank();
  }
}

contract Initialize is ZkTokenV3ForkTest {
  function test_UpgradeTransparentUpgradeableProxyFromTokenV2ToTokenV3() public {
    ProxyAdmin _proxy = ProxyAdmin(payable(PROXY_ADMIN_ADDRESS));
    ZkTokenV2 _tokenV2 = ZkTokenV2(payable(ZK_TOKEN_PROXY_ADDRESS));
    uint256 _tokenSupply = _tokenV2.totalSupply();
    ZkTokenV3 _tokenV3Implementation = new ZkTokenV3();

    vm.prank(_proxy.owner());
    _proxy.upgrade(ITransparentUpgradeableProxy(ZK_TOKEN_PROXY_ADDRESS), address(_tokenV3Implementation));

    assertEq(
      _proxy.getProxyImplementation(ITransparentUpgradeableProxy(ZK_TOKEN_PROXY_ADDRESS)),
      address(_tokenV3Implementation)
    );
    assertEq(tokenV3.symbol(), "ZK");
    assertEq(tokenV3.name(), "ZKsync");
    assertEq(tokenV3.totalSupply(), _tokenSupply);
  }

  function testForkFuzz_RevertIf_TheInitializerIsCalled(
    address _admin,
    address _initMintReceiver,
    uint256 _initialMintAmount
  ) public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3.initialize(_admin, _initMintReceiver, _initialMintAmount);
  }

  function test_RevertIf_TheInitializerV2IsCalledTwice() public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV3.initializeV2();
  }
}

contract Transfer is ZkTokenV3ForkTest {
  function testForkFuzz_CallerCanTransferTokens(
    uint256 _initialBalance,
    uint256 _transferAmount,
    address _caller,
    address _to
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_to != address(0));
    _initialBalance = bound(_initialBalance, 0, type(uint208).max - tokenV3.totalSupply());
    _transferAmount = bound(_transferAmount, 0, _initialBalance);
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_caller, _initialBalance);

    vm.prank(_caller);
    tokenV3.transfer(_to, _transferAmount);

    assertEq(tokenV3.balanceOf(_caller), _initialBalance - _transferAmount);
    assertEq(tokenV3.balanceOf(_to), _transferAmount);
  }
}

contract TransferFrom is ZkTokenV3ForkTest {
  function testForkFuzz_CallerCanTransferTokensFromAnotherAddress(
    uint256 _initialBalance,
    uint256 _transferAmount,
    address _caller,
    address _from,
    address _to
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != PROXY_ADMIN_ADDRESS);
    vm.assume(_to != address(0));
    _initialBalance = bound(_initialBalance, 0, type(uint208).max - tokenV3.totalSupply());
    _transferAmount = bound(_transferAmount, 0, _initialBalance);
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_from, _initialBalance);

    vm.prank(_from);
    tokenV3.approve(_caller, _transferAmount);

    vm.prank(_caller);
    tokenV3.transferFrom(_from, _to, _transferAmount);
  }
}

contract Delegate is ZkTokenV3ForkTest {
  function testForkFuzz_CallerCanDelegateTokens(
    uint256 _initialBalance,
    uint256 _delegateAmount,
    address _caller,
    address _delegatee
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, type(uint208).max - tokenV3.totalSupply());
    _delegateAmount = bound(_delegateAmount, 0, _initialBalance);
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_caller, _initialBalance);

    vm.prank(_caller);
    tokenV3.delegate(_delegatee);

    assertEq(tokenV3.delegates(_caller), _delegatee);
  }

  function testForkFuzz_HolderAbleToDelegateAfterReceivingTokens(
    address _caller,
    address _to,
    uint256 _initialBalance,
    uint256 _amount
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, type(uint208).max - tokenV3.totalSupply());
    _amount = bound(_amount, 0, _initialBalance);

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_caller, _initialBalance);

    // Transfer
    vm.prank(_caller);
    tokenV3.transfer(_to, _amount);
    assertEq(tokenV3.balanceOf(_caller), _initialBalance - _amount);
    assertEq(tokenV3.balanceOf(_to), _amount);

    // Approve
    vm.prank(_caller);
    tokenV3.approve(_to, _initialBalance - _amount);
    assertEq(tokenV3.allowance(_caller, _to), _initialBalance - _amount);

    // TransferFrom
    vm.prank(_to);
    tokenV3.transferFrom(_caller, _to, _initialBalance - _amount);
    assertEq(tokenV3.balanceOf(_caller), 0);
    assertEq(tokenV3.balanceOf(_to), _initialBalance);

    // Delegate
    vm.prank(_to);
    tokenV3.delegate(_caller);
    assertEq(tokenV3.delegates(_to), _caller);
  }
}

contract Mint is ZkTokenV3ForkTest {
  function testForkFuzz_GovernorCanMintTokens(uint256 _mintAmount, address _to) public {
    vm.assume(_to != address(0));
    uint256 _initialBalance = tokenV3.balanceOf(_to);
    uint256 _initialSupply = tokenV3.totalSupply();
    vm.assume(_initialSupply <= MAX_SUPPLY);
    uint256 _availableSupply = MAX_SUPPLY - _initialSupply;
    _mintAmount = bound(_mintAmount, 0, _availableSupply);
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_to, _mintAmount);

    assertEq(tokenV3.balanceOf(_to), _initialBalance + _mintAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply + _mintAmount);
  }

  function testForkFuzz_RevertIf_MintsAboveMaxSupply(uint256 _mintAmount, address _to) public {
    vm.assume(_to != address(0));
    uint256 _initialSupply = tokenV3.totalSupply();
    uint256 _maxVotesSupply = type(uint224).max;
    vm.assume(_initialSupply <= MAX_SUPPLY);
    vm.assume(_initialSupply < _maxVotesSupply);
    uint256 _minExcessMint = _maxVotesSupply - _initialSupply + 1;
    _mintAmount = bound(_mintAmount, _minExcessMint, type(uint256).max - _initialSupply);

    vm.expectRevert();
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_to, _mintAmount);
  }

  function testForkFuzz_RevertIf_CallerDoesNotHaveMinterRole(uint256 _mintAmount, address _caller) public {
    vm.assume(_caller != address(0) && _caller != admin);
    _mintAmount = bound(_mintAmount, 0, type(uint208).max - tokenV3.totalSupply());

    vm.expectRevert(_formatAccessControlError(_caller, tokenV3.MINTER_ROLE()));
    vm.prank(_caller);
    tokenV3.mint(_caller, _mintAmount);
  }
}

contract Burn is ZkTokenV3ForkTest {
  function testForkFuzz_CallerCanBurnTokens(uint256 _initialBalance, uint256 _burnAmount, address _caller) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, type(uint208).max - tokenV3.totalSupply());
    _burnAmount = bound(_burnAmount, 0, _initialBalance);
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_caller, _initialBalance);
    uint256 _initialSupply = tokenV3.totalSupply();

    vm.prank(_caller);
    tokenV3.burn(_burnAmount);

    assertEq(tokenV3.balanceOf(_caller), _initialBalance - _burnAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply - _burnAmount);
  }

  function testForkFuzz_RevertIf_CallerDoesNotHaveEnoughBalance(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - tokenV3.totalSupply() - 1);
    _burnAmount = bound(_burnAmount, _initialBalance + 1, MAX_SUPPLY - tokenV3.totalSupply());
    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_caller, _initialBalance);

    vm.prank(_caller);
    vm.expectRevert("ERC20: burn amount exceeds balance");
    tokenV3.burn(_burnAmount);
  }
}

contract BurnFrom is ZkTokenV3ForkTest {
  function testForkFuzz_CallerWithBurnerRoleCanBurnTokensFromAnotherAddress(
    uint256 _mintBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != PROXY_ADMIN_ADDRESS);
    _grantBurnerRole(_caller);
    uint256 _initialSupply = tokenV3.totalSupply();
    _mintBalance = bound(_mintBalance, 0, MAX_SUPPLY - _initialSupply);
    _burnAmount = bound(_burnAmount, 0, _mintBalance);

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_from, _mintBalance);
    uint256 _initialBalance = tokenV3.balanceOf(_from);

    vm.prank(_caller);
    tokenV3.burnFrom(_from, _burnAmount);

    assertEq(tokenV3.balanceOf(_from), _initialBalance - _burnAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply + (_mintBalance - _burnAmount));
  }

  function testForkFuzz_CallerWithBurnerRoleCanBurnTokensUsingOldMethodFromAnotherAddress(
    uint256 _mintAmount,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != PROXY_ADMIN_ADDRESS);
    _grantBurnerRole(_caller);
    uint256 _initialSupply = tokenV3.totalSupply();
    _mintAmount = bound(_mintAmount, 0, MAX_SUPPLY - _initialSupply);
    _burnAmount = bound(_burnAmount, 0, _mintAmount);

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_from, _mintAmount);
    uint256 _initialBalance = tokenV3.balanceOf(_from);

    vm.prank(_caller);
    tokenV3.burn(_from, _burnAmount);

    assertEq(tokenV3.balanceOf(_from), _initialBalance - _burnAmount);
    assertEq(tokenV3.totalSupply(), _initialSupply + (_mintAmount - _burnAmount));
  }

  function testForkFuzz_RevertIf_CallerDoesNotHaveBurnerRole(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - tokenV3.totalSupply());
    _burnAmount = bound(_burnAmount, 0, _initialBalance);

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_from, _initialBalance);

    vm.prank(_caller);
    vm.expectRevert(_formatAccessControlError(_caller, BURNER_ROLE));
    tokenV3.burnFrom(_from, _burnAmount);
  }

  function testForkFuzz_RevertIf_CallerDoesNotHaveBurnerRoleUsingOldMethod(
    uint256 _initialBalance,
    uint256 _burnAmount,
    address _caller,
    address _from
  ) public {
    vm.assume(_caller != address(0) && _caller != PROXY_ADMIN_ADDRESS);
    vm.assume(_from != address(0) && _from != PROXY_ADMIN_ADDRESS);
    _initialBalance = bound(_initialBalance, 0, MAX_SUPPLY - tokenV3.totalSupply());
    _burnAmount = bound(_burnAmount, 0, _initialBalance);

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_from, _initialBalance);

    vm.prank(_caller);
    vm.expectRevert(_formatAccessControlError(_caller, BURNER_ROLE));
    tokenV3.burn(_from, _burnAmount);
  }
}

contract DelegateOnBehalf is ZkTokenV3ForkTest {
  /// @notice Type hash used when encoding data for `delegateOnBehalf` calls.
  bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address owner,address delegatee,uint256 nonce,uint256 expiry)");

  function testForkFuzz_PerformsDelegationByCallingDelegateOnBehalfECDSA(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, block.timestamp, type(uint256).max);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_SUPPLY - tokenV3.totalSupply());

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(tokenV3.balanceOf(_signer), _amount);

    bytes32 _message = keccak256(abi.encode(DELEGATION_TYPEHASH, _signer, _delegatee, tokenV3.nonces(_signer), _expiry));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", tokenV3.DOMAIN_SEPARATOR(), _message));
    (uint8 _v, bytes32 _r, bytes32 _s) = vm.sign(_signerPrivateKey, _messageHash);

    // verify the signer has no delegate
    assertEq(tokenV3.delegates(_signer), address(0));

    tokenV3.delegateOnBehalf(_signer, _delegatee, _expiry, abi.encodePacked(_r, _s, _v));

    // verify the signer has delegate
    assertEq(tokenV3.delegates(_signer), _delegatee);
  }

  function testForkFuzz_PerformsDelegationByCallingDelegateOnBehalfEIP1271(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, block.timestamp, type(uint256).max);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_SUPPLY - tokenV3.totalSupply());

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(tokenV3.balanceOf(_signer), _amount);

    bytes32 _message = keccak256(abi.encode(DELEGATION_TYPEHASH, _signer, _delegatee, tokenV3.nonces(_signer), _expiry));

    bytes32 _messageHash = keccak256(abi.encodePacked("\x19\x01", tokenV3.DOMAIN_SEPARATOR(), _message));

    // verify the signer has no delegate
    assertEq(tokenV3.delegates(_signer), address(0));

    vm.mockCall(
      _signer,
      abi.encodeWithSelector(IERC1271.isValidSignature.selector, _messageHash),
      abi.encode(IERC1271.isValidSignature.selector)
    );

    tokenV3.delegateOnBehalf(_signer, _delegatee, _expiry, "");

    // verify the signer has delegate
    assertEq(tokenV3.delegates(_signer), _delegatee);
  }

  function testForkFuzz_RevertIf_ExpiredSignatureDelegateOnBehalf(
    uint256 _signerPrivateKey,
    uint256 _amount,
    address _delegatee,
    uint256 _expiry
  ) public {
    vm.assume(_delegatee != address(0));
    _expiry = bound(_expiry, 0, block.timestamp - 1);
    _signerPrivateKey = bound(_signerPrivateKey, 1, 100e18);
    address _signer = vm.addr(_signerPrivateKey);
    _amount = bound(_amount, 0, MAX_SUPPLY - tokenV3.totalSupply());

    vm.prank(TOKEN_GOVERNOR_TIMELOCK);
    tokenV3.mint(_signer, _amount);

    // verify the owner has the expected balance
    assertEq(tokenV3.balanceOf(_signer), _amount);

    // verify the signer has no delegate
    assertEq(tokenV3.delegates(_signer), address(0));

    vm.expectRevert(abi.encodeWithSelector(ZkTokenV1.DelegateSignatureExpired.selector, _expiry));
    tokenV3.delegateOnBehalf(_signer, _delegatee, _expiry, "");
  }
}
