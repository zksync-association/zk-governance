// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {ZkCappedMinterV2Factory} from "src/ZkCappedMinterV2Factory.sol";
import {ZkCappedMinterV2} from "src/ZkCappedMinterV2.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ZkCappedMinterV2FactoryTest is ZkTokenTest {
  bytes32 bytecodeHash;
  ZkCappedMinterV2Factory factory;

  function setUp() public virtual override {
    super.setUp();

    // Read the bytecode hash from the JSON file
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/zkout/ZkCappedMinterV2.sol/ZkCappedMinterV2.json");
    string memory json = vm.readFile(path);
    bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

    factory = new ZkCappedMinterV2Factory(bytecodeHash);
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(factory));
  }

  function _boundToReasonableCap(uint256 _cap) internal view returns (uint256) {
    return bound(_cap, 1, MAX_MINT_SUPPLY);
  }
}

contract CreateCappedMinter is ZkCappedMinterV2FactoryTest {
  function testFuzz_CreatesNewCappedMinter(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address minterAddress =
      factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    ZkCappedMinterV2 minter = ZkCappedMinterV2(minterAddress);
    assertEq(address(minter.TOKEN()), address(token));
    assertEq(minter.ADMIN(), _cappedMinterAdmin);
    assertEq(minter.CAP(), _cap);
  }

  function testFuzz_EmitsCappedMinterCreatedEvent(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    vm.expectEmit();
    emit ZkCappedMinterV2Factory.CappedMinterV2Created(
      factory.getMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce),
      IMintableAndDelegatable(address(token)),
      _cappedMinterAdmin,
      _cap
    );

    factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce)
    public
  {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    vm.expectRevert("Code hash is non-zero");
    factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);
  }
}

contract GetMinter is ZkCappedMinterV2FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address expectedMinterAddress =
      factory.getMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    address minterAddress =
      factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    assertEq(minterAddress, expectedMinterAddress);
  }

  function testFuzz_GetMinterWithoutDeployment(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address expectedMinterAddress =
      factory.getMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    uint256 codeSize;
    assembly {
      codeSize := extcodesize(expectedMinterAddress)
    }
    assertEq(codeSize, 0);

    address minterAddress =
      factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    assembly {
      codeSize := extcodesize(expectedMinterAddress)
    }
    assertGt(codeSize, 0);
    assertEq(minterAddress, expectedMinterAddress);
  }
}
