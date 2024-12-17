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

  function _boundToValidTimeControls(uint48 _startTime, uint48 _expirationTime) internal view returns (uint48, uint48) {
    {
      // Using uint32 for time controls to prevent overflows in the ZkToken contract regarding block numbers needing to
      // be
      // casted to uint32.
      _startTime = uint48(bound(_startTime, vm.getBlockTimestamp() + 1, type(uint32).max - 1));
      _expirationTime = uint48(bound(_expirationTime, _startTime + 1, type(uint32).max));
      return (_startTime, _expirationTime);
    }
  }
}

contract CreateCappedMinter is ZkCappedMinterV2FactoryTest {
  function testFuzz_CreatesNewCappedMinter(
    address _cappedMinterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address minterAddress = factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    ZkCappedMinterV2 minter = ZkCappedMinterV2(minterAddress);
    assertEq(address(minter.TOKEN()), address(token));
    assertEq(minter.hasRole(DEFAULT_ADMIN_ROLE, _cappedMinterAdmin), true);
    assertEq(minter.CAP(), _cap);
  }

  function testFuzz_EmitsCappedMinterCreatedEvent(
    address _cappedMinterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    vm.expectEmit();
    emit ZkCappedMinterV2Factory.CappedMinterV2Created(
      factory.getMinter(
        IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
      ),
      IMintableAndDelegatable(address(token)),
      _cappedMinterAdmin,
      _cap,
      _startTime,
      _expirationTime
    );

    factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );
  }

  function testFuzz_RevertIf_CreatingDuplicateMinter(
    address _cappedMinterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    vm.expectRevert("Code hash is non-zero");
    factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );
  }
}

contract GetMinter is ZkCappedMinterV2FactoryTest {
  function testFuzz_ReturnsCorrectMinterAddress(
    address _cappedMinterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address expectedMinterAddress = factory.getMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    address minterAddress = factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    assertEq(minterAddress, expectedMinterAddress);
  }

  function testFuzz_GetMinterWithoutDeployment(
    address _cappedMinterAdmin,
    uint256 _cap,
    uint48 _startTime,
    uint48 _expirationTime,
    uint256 _saltNonce
  ) public {
    (_startTime, _expirationTime) = _boundToValidTimeControls(_startTime, _expirationTime);

    _assumeValidAddress(_cappedMinterAdmin);
    _cap = _boundToReasonableCap(_cap);

    address expectedMinterAddress = factory.getMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    uint256 codeSize;
    assembly {
      codeSize := extcodesize(expectedMinterAddress)
    }
    assertEq(codeSize, 0);

    address minterAddress = factory.createCappedMinter(
      IMintableAndDelegatable(address(token)), _cappedMinterAdmin, _cap, _startTime, _expirationTime, _saltNonce
    );

    assembly {
      codeSize := extcodesize(expectedMinterAddress)
    }
    assertGt(codeSize, 0);
    assertEq(minterAddress, expectedMinterAddress);
  }
}
