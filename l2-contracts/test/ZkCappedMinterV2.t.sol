// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ZkCappedMinterV2} from "src/ZkCappedMinterV2.sol";
import {console2} from "forge-std/Test.sol";

contract ZkCappedMinterV2Test is ZkTokenTest {
  ZkCappedMinterV2 public cappedMinter;
  uint256 constant DEFAULT_CAP = 100_000_000e18;
  address cappedMinterAdmin = makeAddr("cappedMinterAdmin");

  function setUp() public virtual override {
    super.setUp();

    cappedMinter = _createCappedMinter(cappedMinterAdmin, DEFAULT_CAP);

    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(cappedMinter));
  }

  function _createCappedMinter(address _admin, uint256 _cap) internal returns (ZkCappedMinterV2) {
    return new ZkCappedMinterV2(IMintableAndDelegatable(address(token)), _admin, _cap);
  }

  function _grantMinterRole(ZkCappedMinterV2 _cappedMinter, address _cappedMinterAdmin, address _minter) internal {
    vm.prank(_cappedMinterAdmin);
    _cappedMinter.grantRole(MINTER_ROLE, _minter);
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

contract Constructor is ZkCappedMinterV2Test {
  function testFuzz_InitializesTheCappedMinterForAssociationAndFoundation(address _cappedMinterAdmin, uint256 _cap)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    ZkCappedMinterV2 cappedMinter = _createCappedMinter(_cappedMinterAdmin, _cap);
    assertEq(address(cappedMinter.TOKEN()), address(token));
    assertEq(cappedMinter.hasRole(DEFAULT_ADMIN_ROLE, _cappedMinterAdmin), true);
    assertEq(cappedMinter.CAP(), _cap);
  }
}

contract Mint is ZkCappedMinterV2Test {
  function testFuzz_MintsNewTokensWhenTheAmountRequestedIsBelowTheCap(
    address _minter,
    address _receiver,
    uint256 _amount
  ) public {
    vm.assume(_receiver != address(0));
    _amount = bound(_amount, 1, DEFAULT_CAP);

    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    uint256 balanceBefore = token.balanceOf(_receiver);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), balanceBefore + _amount);
  }

  function testFuzz_MintsNewTokensInSuccessionToDifferentAccountsWhileRemainingBelowCap(
    address _minter,
    address _receiver1,
    address _receiver2,
    uint256 _amount1,
    uint256 _amount2
  ) public {
    _amount1 = bound(_amount1, 1, DEFAULT_CAP / 2);
    _amount2 = bound(_amount2, 1, DEFAULT_CAP / 2);
    vm.assume(_amount1 + _amount2 < DEFAULT_CAP);
    vm.assume(_receiver1 != address(0) && _receiver2 != address(0));
    vm.assume(_receiver1 != _receiver2);

    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    uint256 balanceBefore1 = token.balanceOf(_receiver1);
    uint256 balanceBefore2 = token.balanceOf(_receiver2);

    vm.startPrank(_minter);
    cappedMinter.mint(_receiver1, _amount1);
    cappedMinter.mint(_receiver2, _amount2);
    vm.stopPrank();

    assertEq(token.balanceOf(_receiver1), balanceBefore1 + _amount1);
    assertEq(token.balanceOf(_receiver2), balanceBefore2 + _amount2);
  }

  function testFuzz_RevertIf_MintAttemptedByNonMinter(address _nonMinter, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    vm.expectRevert(_formatAccessControlError(_nonMinter, MINTER_ROLE));
    vm.prank(_nonMinter);
    cappedMinter.mint(_nonMinter, _amount);
  }

  function testFuzz_RevertIf_CapExceededOnMint(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, DEFAULT_CAP + 1, type(uint256).max);
    vm.assume(_receiver != address(0));

    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__CapExceeded.selector, _minter, _amount));
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_AdminAttemptsToMintByDefault(address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, MINTER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_CorrectlyPermanentlyBlocksMinting(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    vm.prank(cappedMinterAdmin);
    cappedMinter.grantRole(MINTER_ROLE, _minter);

    vm.prank(cappedMinterAdmin);
    cappedMinter.close();

    vm.expectRevert(ZkCappedMinterV2.ZkCappedMinterV2__ContractClosed.selector);
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }
}

contract Pause is ZkCappedMinterV2Test {
  function testFuzz_CorrectlyPreventsNewMintsWhenPaused(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    // Grant minter role and verify minting works
    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    uint256 balanceBefore = token.balanceOf(_receiver);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), balanceBefore + _amount);

    // Pause and verify minting fails
    vm.prank(cappedMinterAdmin);
    cappedMinter.pause();

    vm.expectRevert("Pausable: paused");
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_CorrectlyPausesMintsWhenTogglingPause(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    vm.startPrank(cappedMinterAdmin);
    cappedMinter.pause();
    cappedMinter.unpause();
    cappedMinter.pause();
    vm.stopPrank();

    vm.expectRevert("Pausable: paused");
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_NotPauserRolePauses(uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    // Remove PAUSER_ROLE from admin
    vm.prank(cappedMinterAdmin);
    cappedMinter.revokeRole(PAUSER_ROLE, cappedMinterAdmin);

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, PAUSER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinter.pause();
  }
}

contract Unpause is ZkCappedMinterV2Test {
  function testFuzz_CorrectlyAllowsNewMintsWhenUnpaused(address _minter, address _receiver, uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);
    vm.assume(_receiver != address(0));

    _grantMinterRole(cappedMinter, cappedMinterAdmin, _minter);

    vm.prank(cappedMinterAdmin);
    cappedMinter.pause();

    vm.prank(cappedMinterAdmin);
    cappedMinter.unpause();

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
  }

  function testFuzz_RevertIf_NotPauserRoleUnpauses(uint256 _amount) public {
    _amount = bound(_amount, 1, DEFAULT_CAP);

    // Pause first (while admin still has PAUSER_ROLE)
    vm.prank(cappedMinterAdmin);
    cappedMinter.pause();

    // Remove PAUSER_ROLE from admin
    vm.prank(cappedMinterAdmin);
    cappedMinter.revokeRole(PAUSER_ROLE, cappedMinterAdmin);

    vm.expectRevert(_formatAccessControlError(cappedMinterAdmin, PAUSER_ROLE));
    vm.prank(cappedMinterAdmin);
    cappedMinter.unpause();
  }
}

contract Close is ZkCappedMinterV2Test {
  function test_CorrectlyChangesClosedVarWhenCalledByAdmin() public {
    assertEq(cappedMinter.closed(), false);

    vm.prank(cappedMinterAdmin);
    cappedMinter.close();
    assertEq(cappedMinter.closed(), true);
  }

  function testFuzz_RevertIf_NotAdminCloses(address _nonAdmin) public {
    vm.assume(_nonAdmin != cappedMinterAdmin);
    vm.expectRevert(_formatAccessControlError(_nonAdmin, DEFAULT_ADMIN_ROLE));
    vm.prank(_nonAdmin);
    cappedMinter.close();
  }
}
