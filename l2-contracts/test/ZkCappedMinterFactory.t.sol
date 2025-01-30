// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ZkTokenTest} from "test/utils/ZkTokenTest.sol";
import {ZkCappedMinterFactory} from "src/ZkCappedMinterFactory.sol";
import {ZkCappedMinter} from "src/ZkCappedMinter.sol";
import {IMintableAndDelegatable} from "src/interfaces/IMintableAndDelegatable.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {console2} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract ZkCappedMinterFactoryTest is ZkTokenTest {
  bytes32 bytecodeHash;
  ZkCappedMinterFactory factory;

  function setUp() public virtual override {
    super.setUp();

    // Read the bytecode hash from the JSON file
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/zkout/ZkCappedMinter.sol/ZkCappedMinter.json");
    string memory json = vm.readFile(path);
    bytecodeHash = bytes32(stdJson.readBytes(json, ".hash"));

    factory = new ZkCappedMinterFactory(bytecodeHash);
  }

  function _assumeValidAddress(address _addr) internal view {
    vm.assume(_addr != address(0) && _addr != address(factory));
  }

  function _boundToReasonableCap(uint256 _cap) internal view returns (uint256) {
    return bound(_cap, 1, MAX_MINT_SUPPLY);
  }
}

contract CreateCappedMinter is ZkCappedMinterFactoryTest {
  function testFuzz_CreatesNewCappedMinter(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address minterAddress =
      factory.createCappedMinter(IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _saltNonce);

    ZkCappedMinter minter = ZkCappedMinter(minterAddress);
    assertEq(address(minter.TOKEN()), address(token));
    assertEq(minter.ADMIN(), _cappedMinterAdmin);
    assertEq(minter.CAP(), _cap);
  }

  function testFuzz_EmitsCappedMinterCreatedEvent(address _cappedMinterAdmin, uint256 _cap, uint256 _saltNonce) public {
    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    vm.expectEmit();
    emit ZkCappedMinterFactory.CappedMinterCreated(
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

contract GetMinter is ZkCappedMinterFactoryTest {
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
