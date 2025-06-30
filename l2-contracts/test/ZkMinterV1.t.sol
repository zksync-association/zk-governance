// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkMinterRateLimiterV1} from "src/ZkMinterRateLimiterV1.sol";
import {ZkMinterV1} from "src/ZkMinterV1.sol";
import {ZkCappedMinterV2Test} from "test/ZkCappedMinterV2.t.sol";
import {IMintable} from "src/interfaces/IMintable.sol";

contract ZkMinterV1Test is ZkCappedMinterV2Test {
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

contract Close is ZkMinterV1Test {
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
    emit ZkMinterV1.Closed(_closer);
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

contract UpdateMintable is ZkMinterV1Test {
  function testFuzz_AdminCanUpdateMintable(IMintable _newMintable) public {
    vm.prank(admin);
    minterRateLimiter.updateMintable(_newMintable);
    assertEq(address(minterRateLimiter.mintable()), address(_newMintable));
  }

  function testFuzz_EmitsMintableUpdatedEvent(IMintable _newMintable) public {
    vm.startPrank(admin);
    vm.expectEmit();
    emit ZkMinterV1.MintableUpdated(minterRateLimiter.mintable(), _newMintable);
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

  function testFuzz_RevertIf_CalledAfterContractIsClosed(IMintable _newMintable) public {
    vm.prank(admin);
    minterRateLimiter.close();

    vm.startPrank(admin);
    vm.expectRevert(ZkMinterV1.ZkMinter__ContractClosed.selector);
    minterRateLimiter.updateMintable(_newMintable);
    vm.stopPrank();
  }
}

contract Pause is ZkMinterV1Test {
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

contract Unpause is ZkMinterV1Test {
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

contract GrantRole is ZkMinterV1Test {
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

contract RenounceRole is ZkMinterV1Test {
  function testFuzz_AdminCanRenounceAdminRole(address _renouncer) public {
    vm.prank(admin);
    minterRateLimiter.grantRole(DEFAULT_ADMIN_ROLE, _renouncer);

    vm.prank(_renouncer);
    minterRateLimiter.renounceRole(DEFAULT_ADMIN_ROLE, _renouncer);
    assertEq(minterRateLimiter.hasRole(DEFAULT_ADMIN_ROLE, _renouncer), false);
  }
}
