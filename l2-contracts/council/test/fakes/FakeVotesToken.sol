// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// A votes token with an open `mint` and a timestamp clock, matching the ZK token's clock mode.
contract FakeVotesToken is ERC20Votes {
  constructor() ERC20("Fake Votes Token", "FAKE") EIP712("Fake Votes Token", "1") {}

  function mint(address _account, uint256 _amount) external {
    _mint(_account, _amount);
  }

  function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
  }

  function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
  }
}
