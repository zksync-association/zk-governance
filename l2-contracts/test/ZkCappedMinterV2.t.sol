// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ZkCappedMinterV2} from "src/ZkCappedMinterV2.sol";
import {console2} from "forge-std/Test.sol";

contract ZkCappedMinterV2Test is ZkTokenTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function _createCappedMinter(address _admin, uint256 _cap, uint256 _startTime, uint256 _expirationTime)
    internal
    returns (ZkCappedMinterV2)
  {
    ZkCappedMinterV2 cappedMinter =
      new ZkCappedMinterV2(IMintableAndDelegatable(address(token)), _admin, _cap, _startTime, _expirationTime);
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(cappedMinter));
    return cappedMinter;
  }

  function _boundToValidTimeControls(uint256 _startTime, uint256 _expirationTime)
    internal
    view
    returns (uint256, uint256)
  {
    // Using uint32 for time controls to prevent overflows in the ZkToken contract regarding block numbers needing to be
    // casted to uint32.
    _startTime = bound(_startTime, vm.getBlockTimestamp(), type(uint32).max - 1);
    _expirationTime = bound(_expirationTime, _startTime + 1, type(uint32).max);
    return (_startTime, _expirationTime);
  }
}

contract Constructor is ZkCappedMinterV2Test {
  function testFuzz_InitializesTheCappedMinterForAssociationAndFoundation(
    address _admin,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);
    assertEq(address(cappedMinter.TOKEN()), address(token));
    assertEq(cappedMinter.CAP(), _cap);
    assertEq(cappedMinter.START_TIME(), _startTime);
    assertEq(cappedMinter.EXPIRATION_TIME(), _expirationTime);
  }

  function testFuzz_RevertIf_StartTimeAfterExpirationTime(
    address _admin,
    uint256 _cap,
    uint256 _startTime,
    uint256 _invalidExpirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    _startTime = bound(_startTime, vm.getBlockTimestamp() + 1, type(uint256).max - 1);
    vm.warp(_startTime);
    _invalidExpirationTime = bound(_invalidExpirationTime, 0, _startTime);

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__InvalidTime.selector);
    _createCappedMinter(_admin, _cap, _startTime, _invalidExpirationTime);
  }

  function testFuzz_RevertIf_StartTimeInPast(address _admin, uint256 _cap, uint256 _pastTime, uint256 _expirationTime)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    _pastTime = bound(_pastTime, 0, vm.getBlockTimestamp() - 1);
    _expirationTime = bound(_expirationTime, vm.getBlockTimestamp() + 1, type(uint256).max);

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__InvalidTime.selector);
    _createCappedMinter(_admin, _cap, _pastTime, _expirationTime);
  }
}

contract Mint is ZkCappedMinterV2Test {
  function testFuzz_MintsNewTokensWhenTheAmountRequestedIsBelowTheCap(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, MAX_MINT_SUPPLY);
    vm.assume(_cap > _amount);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    vm.assume(_minter != address(0));
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_MintsNewTokensInSuccessionToDifferentAccountsWhileRemainingBelowCap(
    address _admin,
    address _minter,
    address _receiver1,
    address _receiver2,
    uint256 _cap,
    uint256 _amount1,
    uint256 _amount2,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);
    vm.assume(_cap > 0);
    vm.assume(_amount1 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount2 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount1 + _amount2 < _cap);
    vm.assume(_receiver1 != address(0) && _receiver1 != initMintReceiver);
    vm.assume(_receiver2 != address(0) && _receiver2 != initMintReceiver);
    vm.assume(_receiver1 != _receiver2);
    vm.assume(_minter != address(0));

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.startPrank(_minter);
    cappedMinter.mint(_receiver1, _amount1);
    cappedMinter.mint(_receiver2, _amount2);
    vm.stopPrank();

    assertEq(token.balanceOf(_receiver1), _amount1);
    assertEq(token.balanceOf(_receiver2), _amount2);
  }

  function testFuzz_RevertIf_MintAttemptedByNonMinter(
    address _admin,
    address _nonMinter,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_admin != address(0));
    vm.assume(_nonMinter != address(0) && _nonMinter != _admin);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__NotMinter.selector, _nonMinter));
    vm.prank(_nonMinter);
    cappedMinter.mint(_nonMinter, _cap);
  }

  function testFuzz_RevertIf_CapExceededOnMint(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 4, MAX_MINT_SUPPLY);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    vm.assume(_minter != address(0));
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _cap);
    assertEq(token.balanceOf(_receiver), _cap);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__CapExceeded.selector, _minter, _cap));
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _cap);
  }

  function testFuzz_RevertIf_AdminAttemptsToMintByDefault(
    address _admin,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    vm.assume(_admin != address(0));
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__NotMinter.selector, _admin));
    vm.prank(_admin);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_MintBeforeStartTime(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    _startTime = bound(_startTime, vm.getBlockTimestamp() + 1 hours, type(uint32).max - 1);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _startTime + 1);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__NotStarted.selector);
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_MintAtOrAfterExpiration(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    _startTime = bound(_startTime, vm.getBlockTimestamp() + 1, type(uint32).max - 1);
    _expirationTime = bound(_expirationTime, _startTime + 1, type(uint32).max);
    vm.warp(_startTime);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    // Warp to expiration time
    vm.warp(_expirationTime);

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__Expired.selector);
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);

    // Warp to expiration time + 1
    vm.warp(_expirationTime + 1);

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__Expired.selector);
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }
}

contract Pause is ZkCappedMinterV2Test {
  function testFuzz_CorrectlyPreventsNewMintsWhenPaused(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    vm.assume(_admin != address(0));
    vm.assume(_minter != address(0) && _minter != _admin);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    // Grant minter role and verify minting works
    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), _amount);

    // Pause and verify minting fails
    vm.prank(_admin);
    cappedMinter.pause();

    vm.expectRevert("Pausable: paused");
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_NotPauserRolePauses(
    address _admin,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_admin != address(0));
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    // Remove PAUSER_ROLE from admin
    vm.prank(_admin);
    cappedMinter.revokeRole(PAUSER_ROLE, _admin);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__NotPauser.selector, _admin));
    vm.prank(_admin);
    cappedMinter.pause();
  }
}

contract Unpause is ZkCappedMinterV2Test {
  function testFuzz_CorrectlyAllowsNewMintsWhenUnpaused(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    vm.assume(_admin != address(0));
    vm.assume(_minter != address(0) && _minter != _admin);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_admin);
    cappedMinter.pause();

    vm.prank(_admin);
    cappedMinter.unpause();

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_RevertIf_NotPauserRoleUnpauses(
    address _admin,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_admin != address(0));
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    // Pause first (while admin still has PAUSER_ROLE)
    vm.prank(_admin);
    cappedMinter.pause();

    // Remove PAUSER_ROLE from admin
    vm.prank(_admin);
    cappedMinter.revokeRole(PAUSER_ROLE, _admin);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__NotPauser.selector, _admin));
    vm.prank(_admin);
    cappedMinter.unpause();
  }
}

contract Close is ZkCappedMinterV2Test {
  function testFuzz_CorrectlyPermanentlyBlocksMinting(
    address _admin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.prank(_admin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(_admin);
    cappedMinter.close();

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__ContractClosed.selector);
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);

    // Try to unpause (should fail)
    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__ContractClosed.selector);
    vm.prank(_admin);
    cappedMinter.unpause();
  }

  function testFuzz_RevertIf_NotPauserRoleCloses(
    address _admin,
    address _nonPauser,
    uint256 _cap,
    uint256 _startTime,
    uint256 _expirationTime
  ) public {
    vm.assume(_nonPauser != _admin);
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);
    vm.warp(_startTime);

    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_admin, _cap, _startTime, _expirationTime);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__NotPauser.selector, _nonPauser));
    vm.prank(_nonPauser);
    cappedMinter.close();
  }
}
