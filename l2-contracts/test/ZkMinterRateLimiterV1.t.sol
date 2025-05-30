// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterRateLimiterV1} from "src/ZkMinterRateLimiterV1.sol";
import {ZkCappedMinterV2Test} from "test/ZkCappedMinterV2.t.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

contract ZkMinterRateLimiterV1Test is ZkCappedMinterV2Test {
  ZkMinterRateLimiterV1 public minterRateLimiter;
  IMintable public mintable;
  uint256 public constant MINT_RATE_LIMIT = 100_000e18;
  uint48 public constant MINT_RATE_LIMIT_WINDOW = 1 days;

  function setUp() public virtual override {
    super.setUp();
    mintable = IMintable(address(cappedMinter));
    minterRateLimiter = new ZkMinterRateLimiterV1(mintable, admin, MINT_RATE_LIMIT, MINT_RATE_LIMIT_WINDOW);
    _grantMinterRole(cappedMinter, cappedMinterAdmin, address(minterRateLimiter));
  }

  function _grantRateLimiterMinterRole(address _minter) internal {
    vm.prank(admin);
    minterRateLimiter.grantRole(MINTER_ROLE, _minter);
  }

  function test_InitializesMinterRateLimiterCorrectly() public {
    assertTrue(minterRateLimiter.hasRole(minterRateLimiter.DEFAULT_ADMIN_ROLE(), admin));
    assertTrue(minterRateLimiter.hasRole(minterRateLimiter.PAUSER_ROLE(), admin));
    assertEq(address(minterRateLimiter.mintable()), address(mintable));
    assertEq(minterRateLimiter.mintRateLimit(), MINT_RATE_LIMIT);
    assertEq(minterRateLimiter.mintRateLimitWindow(), MINT_RATE_LIMIT_WINDOW);
  }
}

contract Constructor is ZkMinterRateLimiterV1Test {
  function testFuzz_InitializesMinterRateLimiterCorrectly(
    IMintable _mintable,
    address _admin,
    uint256 _mintRateLimit,
    uint48 _mintRateLimitWindow
  ) public {
    ZkMinterRateLimiterV1 _minterRateLimiter =
      new ZkMinterRateLimiterV1(_mintable, _admin, _mintRateLimit, _mintRateLimitWindow);

    assertEq(address(_minterRateLimiter.mintable()), address(_mintable));
    assertTrue(_minterRateLimiter.hasRole(_minterRateLimiter.DEFAULT_ADMIN_ROLE(), _admin));
    assertEq(_minterRateLimiter.mintRateLimit(), _mintRateLimit);
    assertEq(_minterRateLimiter.mintRateLimitWindow(), _mintRateLimitWindow);
  }
}

contract Mint is ZkMinterRateLimiterV1Test {
  address public minter = makeAddr("minter");

  function setUp() public override {
    super.setUp();
    vm.startPrank(admin);
    minterRateLimiter.grantRole(MINTER_ROLE, minter);
    vm.stopPrank();
  }

  function testFuzz_MintsSuccessfullyAsMinter(address _minter, address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, MINT_RATE_LIMIT);
    _grantRateLimiterMinterRole(_minter);

    vm.prank(_minter);
    minterRateLimiter.mint(_to, _amount);
    assertEq(token.balanceOf(_to), _amount);
    assertEq(minterRateLimiter.mintedInWindow(minterRateLimiter.currentMintWindowStart()), _amount);
  }

  function testFuzz_EmitsMintedEvent(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, MINT_RATE_LIMIT);

    vm.prank(minter);
    vm.expectEmit();
    emit ZkMinterRateLimiterV1.Minted(minter, _to, _amount);
    minterRateLimiter.mint(_to, _amount);
  }

  function testFuzz_MintRateLimitIsResetAfterWindow(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, MINT_RATE_LIMIT);

    vm.startPrank(minter);
    // Mint up to 5 times while staying within the IMintable contract's expiration time and mint cap.
    for (
      uint256 i = 0;
      i < 5 && block.timestamp < cappedMinter.EXPIRATION_TIME() && cappedMinter.minted() + _amount < cappedMinter.CAP();
      i++
    ) {
      minterRateLimiter.mint(_to, _amount);
      assertEq(minterRateLimiter.mintedInWindow(minterRateLimiter.currentMintWindowStart()), _amount);
      vm.warp(block.timestamp + MINT_RATE_LIMIT_WINDOW);
    }
    vm.stopPrank();
  }

  function testFuzz_RevertIf_MintRateLimitExceeded(address _to, uint256 _amount) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, MINT_RATE_LIMIT + 1, type(uint256).max);

    vm.prank(minter);
    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterRateLimiterV1.ZkMinterRateLimiterV1__MintRateLimitExceeded.selector, minter, _amount
      )
    );
    minterRateLimiter.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintRateLimitExceededAfterTwoMintsInTheSameWindow(
    address _to,
    uint256 _amount,
    uint256 _exceedingAmount
  ) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, MINT_RATE_LIMIT);
    _exceedingAmount = bound(_exceedingAmount, 1, type(uint256).max);

    vm.startPrank(minter);
    minterRateLimiter.mint(_to, _amount);
    minterRateLimiter.mint(_to, MINT_RATE_LIMIT - _amount);
    assertEq(minterRateLimiter.mintedInWindow(minterRateLimiter.currentMintWindowStart()), MINT_RATE_LIMIT);
    vm.stopPrank();

    vm.prank(minter);
    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterRateLimiterV1.ZkMinterRateLimiterV1__MintRateLimitExceeded.selector, minter, _exceedingAmount
      )
    );
    minterRateLimiter.mint(_to, _exceedingAmount);
  }

  function testFuzz_RevertIf_MintRateLimitExceededAfterTwoMintsInDifferentWindows(
    address _to,
    uint256 _amount,
    uint256 _exceedingAmount
  ) public {
    vm.assume(_to != address(0));
    _amount = bound(_amount, 1, MINT_RATE_LIMIT);
    _exceedingAmount = bound(_exceedingAmount, 1, type(uint256).max);

    vm.startPrank(minter);
    minterRateLimiter.mint(_to, _amount);
    minterRateLimiter.mint(_to, MINT_RATE_LIMIT - _amount);

    vm.warp(block.timestamp + MINT_RATE_LIMIT_WINDOW);

    minterRateLimiter.mint(_to, _amount);
    minterRateLimiter.mint(_to, MINT_RATE_LIMIT - _amount);
    vm.stopPrank();

    vm.prank(minter);
    vm.expectRevert(
      abi.encodeWithSelector(
        ZkMinterRateLimiterV1.ZkMinterRateLimiterV1__MintRateLimitExceeded.selector, minter, _exceedingAmount
      )
    );
    minterRateLimiter.mint(_to, _exceedingAmount);
  }

  function testFuzz_RevertIf_CalledByNonMinter(address _minter, address _nonMinter, address _to, uint256 _amount)
    public
  {
    vm.assume(_nonMinter != _minter && _nonMinter != admin);
    _grantRateLimiterMinterRole(_minter);

    vm.prank(_nonMinter);
    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    minterRateLimiter.mint(_to, _amount);
  }

  function testFuzz_RevertIf_MintAfterContractIsClosed(address _caller, address _to, uint256 _amount) public {
    vm.prank(admin);
    minterRateLimiter.close();

    vm.prank(_caller);
    vm.expectRevert(ZkMinterRateLimiterV1.ZkMinterRateLimiterV1__ContractClosed.selector);
    minterRateLimiter.mint(_to, _amount);
  }
}

contract GrantRole is ZkMinterRateLimiterV1Test {
  function testFuzz_CanGrantAdminRoleToOtherAddresses(address _newAdmin) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    assertTrue(minterRateLimiter.hasRole(DEFAULT_ADMIN_ROLE, _newAdmin));
  }

  function testFuzz_RevertIf_GrantRoleCalledByNonAdmin(address _nonAdmin, address _newAdmin) public {
    vm.assume(_nonAdmin != admin);
    vm.startPrank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _newAdmin);
    vm.stopPrank();
  }
}

contract RenounceRole is ZkMinterRateLimiterV1Test {
  function testFuzz_AdminCanRenounceAdminRole(address _renouncer) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _renouncer);

    vm.prank(_renouncer);
    minterRateLimiter.renounceRole(DEFAULT_ADMIN_ROLE, _renouncer);
    assertEq(minterRateLimiter.hasRole(DEFAULT_ADMIN_ROLE, _renouncer), false);
  }
}

contract Pause is ZkMinterRateLimiterV1Test {
  function testFuzz_PauserCanPauseMinting(address _pauser) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(PAUSER_ROLE, _pauser);

    vm.prank(_pauser);
    minterRateLimiter.pause();
    assertEq(minterRateLimiter.paused(), true);
  }

  function testFuzz_RevertIf_CalledByNonPauser(address _nonPauser) public {
    vm.assume(_nonPauser != admin);
    vm.prank(_nonPauser);
    vm.expectRevert(_formatAccessControlError(_nonPauser, PAUSER_ROLE));
    minterRateLimiter.pause();
  }
}

contract Unpause is ZkMinterRateLimiterV1Test {
  function testFuzz_PauserCanUnpauseMinting(address _pauser) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(PAUSER_ROLE, _pauser);
    vm.prank(admin);
    minterRateLimiter.pause();

    vm.prank(_pauser);
    minterRateLimiter.unpause();
    assertEq(minterRateLimiter.paused(), false);
  }

  function testFuzz_RevertIf_CalledByNonPauser(address _nonPauser) public {
    vm.assume(_nonPauser != admin);
    vm.prank(admin);
    minterRateLimiter.pause();

    vm.prank(_nonPauser);
    vm.expectRevert(_formatAccessControlError(_nonPauser, PAUSER_ROLE));
    minterRateLimiter.unpause();
  }
}

contract Close is ZkMinterRateLimiterV1Test {
  function testFuzz_AdminCanCloseContract(address _closer) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _closer);

    vm.prank(_closer);
    minterRateLimiter.close();
    assertEq(minterRateLimiter.closed(), true);
  }

  function testFuzz_EmitsClosedEvent(address _closer) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _closer);

    vm.prank(_closer);
    vm.expectEmit();
    emit ZkMinterRateLimiterV1.Closed(_closer);
    minterRateLimiter.close();
  }

  function testFuzz_RevertIf_CalledByNonAdmin(address _nonAdmin) public {
    vm.assume(_nonAdmin != admin);
    vm.startPrank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterRateLimiter.close();
    vm.stopPrank();
  }
}

contract UpdateMintable is ZkMinterRateLimiterV1Test {
  function testFuzz_AdminCanUpdateMintable(IMintable _newMintable) public {
    vm.prank(admin);
    minterRateLimiter.updateMintable(_newMintable);
    assertEq(address(minterRateLimiter.mintable()), address(_newMintable));
  }

  function testFuzz_EmitsMintableUpdatedEvent(IMintable _newMintable) public {
    vm.startPrank(admin);
    vm.expectEmit();
    emit ZkMinterRateLimiterV1.MintableUpdated(minterRateLimiter.mintable(), _newMintable);
    minterRateLimiter.updateMintable(_newMintable);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CalledByNonAdmin(address _nonAdmin, IMintable _newMintable) public {
    vm.assume(_nonAdmin != admin);
    vm.startPrank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterRateLimiter.updateMintable(_newMintable);
    vm.stopPrank();
  }
}

contract UpdateMintRateLimit is ZkMinterRateLimiterV1Test {
  function testFuzz_AdminCanUpdateMintRateLimit(uint256 _newMintRateLimit) public {
    vm.prank(admin);
    minterRateLimiter.updateMintRateLimit(_newMintRateLimit);
    assertEq(minterRateLimiter.mintRateLimit(), _newMintRateLimit);
  }

  function testFuzz_EmitsMintRateLimitUpdatedEvent(uint256 _newMintRateLimit) public {
    vm.startPrank(admin);
    vm.expectEmit();
    emit ZkMinterRateLimiterV1.MintRateLimitUpdated(minterRateLimiter.mintRateLimit(), _newMintRateLimit);
    minterRateLimiter.updateMintRateLimit(_newMintRateLimit);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CalledByNonAdmin(address _nonAdmin, uint256 _newMintRateLimit) public {
    vm.assume(_nonAdmin != admin);
    vm.startPrank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterRateLimiter.updateMintRateLimit(_newMintRateLimit);
    vm.stopPrank();
  }
}

contract UpdateMintRateLimitWindow is ZkMinterRateLimiterV1Test {
  function testFuzz_AdminCanUpdateMintRateLimitWindow(uint48 _newMintRateLimitWindow) public {
    vm.prank(admin);
    minterRateLimiter.updateMintRateLimitWindow(_newMintRateLimitWindow);
    assertEq(minterRateLimiter.mintRateLimitWindow(), _newMintRateLimitWindow);
  }

  function testFuzz_EmitsMintRateLimitWindowUpdatedEvent(uint48 _newMintRateLimitWindow) public {
    vm.startPrank(admin);
    vm.expectEmit();
    emit ZkMinterRateLimiterV1.MintRateLimitWindowUpdated(
      minterRateLimiter.mintRateLimitWindow(), _newMintRateLimitWindow
    );
    minterRateLimiter.updateMintRateLimitWindow(_newMintRateLimitWindow);
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CalledByNonAdmin(address _nonAdmin, uint48 _newMintRateLimitWindow) public {
    vm.assume(_nonAdmin != admin);
    vm.startPrank(_nonAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    minterRateLimiter.updateMintRateLimitWindow(_newMintRateLimitWindow);
    vm.stopPrank();
  }
}
