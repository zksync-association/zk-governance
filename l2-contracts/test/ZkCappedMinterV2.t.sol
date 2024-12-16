// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {ZkCappedMinterV2} from "src/ZkCappedMinterV2.sol";
import {console2} from "forge-std/Test.sol";

contract ZkCappedMinterV2Test is ZkTokenTest {
  function setUp() public virtual override {
    super.setUp();
  }

  function createCappedMinter(address _admin, uint256 _cap) internal returns (ZkCappedMinterV2) {
    ZkCappedMinterV2 cappedMinter = new ZkCappedMinterV2(IMintableAndDelegatable(address(token)), _admin, _cap);
    vm.prank(admin);
    token.grantRole(MINTER_ROLE, address(cappedMinter));
    return cappedMinter;
  }

  function _grantMinterRole(ZkCappedMinterV2 _cappedMinter, address _cappedMinterAdmin, address _minter) internal {
    vm.prank(_cappedMinterAdmin);
    _cappedMinter.grantRole(MINTER_ROLE, _minter);
  }
}

contract Constructor is ZkCappedMinterV2Test {
  function testFuzz_InitializesTheCappedMinterForAssociationAndFoundation(address _cappedMinterAdmin, uint256 _cap)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    ZkCappedMinterV2 cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);
    assertEq(address(cappedMinter.TOKEN()), address(token));
    assertEq(cappedMinter.hasRole(DEFAULT_ADMIN_ROLE, _cappedMinterAdmin), true);
    assertEq(cappedMinter.CAP(), _cap);
  }
}

contract Mint is ZkCappedMinterV2Test {
  function testFuzz_MintsNewTokensWhenTheAmountRequestedIsBelowTheCap(
    address _cappedMinterAdmin,
    address _minter,
    address _receiver,
    uint256 _cap,
    uint256 _amount
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    _amount = bound(_amount, 1, MAX_MINT_SUPPLY);
    vm.assume(_cap > _amount);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    vm.assume(_minter != address(0));

    ZkCappedMinterV2 cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);

    _grantMinterRole(cappedMinter, _cappedMinterAdmin, _minter);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _amount);
    assertEq(token.balanceOf(_receiver), _amount);
  }

  function testFuzz_MintsNewTokensInSuccessionToDifferentAccountsWhileRemainingBelowCap(
    address _cappedMinterAdmin,
    address _minter,
    address _receiver1,
    address _receiver2,
    uint256 _cap,
    uint256 _amount1,
    uint256 _amount2
  ) public {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_amount1 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount2 < MAX_MINT_SUPPLY / 2);
    vm.assume(_amount1 + _amount2 < _cap);
    vm.assume(_receiver1 != address(0) && _receiver1 != initMintReceiver);
    vm.assume(_receiver2 != address(0) && _receiver2 != initMintReceiver);
    vm.assume(_receiver1 != _receiver2);
    vm.assume(_minter != address(0));

    ZkCappedMinterV2 cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);

    _grantMinterRole(cappedMinter, _cappedMinterAdmin, _minter);

    vm.startPrank(_minter);
    cappedMinter.mint(_receiver1, _amount1);
    cappedMinter.mint(_receiver2, _amount2);
    vm.stopPrank();

    assertEq(token.balanceOf(_receiver1), _amount1);
    assertEq(token.balanceOf(_receiver2), _amount2);
  }

  function testFuzz_RevertIf_MintAttemptedByNonMinter(address _cappedMinterAdmin, address _nonMinter, uint256 _cap)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    ZkCappedMinterV2 cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);

    vm.assume(_nonMinter != address(0));
    vm.assume(!cappedMinter.hasRole(MINTER_ROLE, _nonMinter));

    vm.expectRevert(
      bytes(
        string.concat(
          "AccessControl: account ",
          Strings.toHexString(uint160(_nonMinter), 20),
          " is missing role ",
          Strings.toHexString(uint256(MINTER_ROLE))
        )
      )
    );
    vm.prank(_nonMinter);
    cappedMinter.mint(_nonMinter, _cap);
  }

  function testFuzz_RevertIf_CapExceededOnMint(
    address _cappedMinterAdmin,
    address _minter,
    address _receiver,
    uint256 _cap
  ) public {
    _cap = bound(_cap, 4, MAX_MINT_SUPPLY);
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);
    vm.assume(_minter != address(0));

    ZkCappedMinterV2 cappedMinter = createCappedMinter(_cappedMinterAdmin, _cap);

    _grantMinterRole(cappedMinter, _cappedMinterAdmin, _minter);

    vm.prank(_minter);
    cappedMinter.mint(_receiver, _cap);
    assertEq(token.balanceOf(_receiver), _cap);

    vm.expectRevert(abi.encodeWithSelector(ZkCappedMinterV2.ZkCappedMinterV2__CapExceeded.selector, _minter, _cap));
    vm.prank(_minter);
    cappedMinter.mint(_receiver, _cap);
  }

  function testFuzz_RevertIf_AdminMintsByDefault(address _admin, address _receiver, uint256 _cap, uint256 _amount)
    public
  {
    _cap = bound(_cap, 0, MAX_MINT_SUPPLY);
    vm.assume(_cap > 0);
    _amount = bound(_amount, 1, _cap);
    vm.assume(_admin != address(0));
    vm.assume(_receiver != address(0) && _receiver != initMintReceiver);

    ZkCappedMinterV2 cappedMinter = createCappedMinter(_admin, _cap);

    vm.expectRevert(
      bytes(
        string.concat(
          "AccessControl: account ",
          Strings.toHexString(uint160(_admin), 20),
          " is missing role ",
          Strings.toHexString(uint256(MINTER_ROLE))
        )
      )
    );
    vm.prank(_admin);
    cappedMinter.mint(_receiver, _amount);
  }
}
