// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20VotesUpgradeable} from
  "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ZkTokenV1 is Initializable, ERC20VotesUpgradeable {
  function initialize() public initializer {
    __ERC20_init("zkSync", "ZK");
  }
}
