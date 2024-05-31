// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkTokenV2} from "src/ZkTokenV2.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract Initialize is Test {
  ZkTokenV2 tokenV2;
  address admin = makeAddr("Admin");
  address initMintReceiver = makeAddr("Init Mint Receiver");

  uint256 INITIAL_MINT_AMOUNT = 1_000_000_000e18;

  // As defined internally in ERC20Votes
  uint256 MAX_MINT_SUPPLY = type(uint208).max - INITIAL_MINT_AMOUNT;

  function setUp() public virtual {
    tokenV2 = new ZkTokenV2();
    tokenV2.initialize(admin, initMintReceiver, INITIAL_MINT_AMOUNT);
    tokenV2.initializeV2();
  }

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

  function test_InitializesTheTokenWithTheCorrectConfigurationWhenDeployedViaUpgrades() public {
    assertEq(tokenV2.symbol(), "ZK");
    assertEq(tokenV2.name(), "ZKsync");

    // verify that the domain separator is setup correctly
    assertEq(tokenV2.DOMAIN_SEPARATOR(), calculateDomainSeparator(address(tokenV2)));
  }

  function testFuzz_InitializesTheTokenWithTheCorrectConfigurationWhenCalledDirectly(
    address _admin,
    address _initMintReceiver,
    uint256 _mintAmount
  ) public {
    vm.assume(_admin != address(0) && _initMintReceiver != address(0) && _admin != _initMintReceiver);
    _mintAmount = bound(_mintAmount, 0, MAX_MINT_SUPPLY);

    ZkTokenV2 _token = new ZkTokenV2();
    _token.initialize(_admin, _initMintReceiver, _mintAmount);
    _token.initializeV2();

    // Same assertions as upgradeable deploy test
    assertEq(_token.balanceOf(_initMintReceiver), _mintAmount);
    assertEq(_token.totalSupply(), _mintAmount);
    assertEq(_token.symbol(), "ZK");
    assertEq(_token.name(), "ZKsync");
  }

  function testFuzz_RevertIf_TheInitializerV2IsCalledTwice(address _admin, address _receiver, uint256 _amount) public {
    vm.expectRevert("Initializable: contract is already initialized");
    tokenV2.initializeV2();
  }
}
