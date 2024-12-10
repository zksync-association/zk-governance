// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintHook} from "src/interfaces/IMintHook.sol";

contract MockMintHook is IMintHook {
  /// @notice Error thrown when the mint amount is too high
  error MockMintHook__AmountTooHigh(uint256 amount, uint256 maxAmount);

  /// @notice Error thrown when the receiver is not allowed
  error MockMintHook__ReceiverNotAllowed(address receiver);

  uint256 public maxAmount;
  mapping(address => bool) public isAllowed;
  bool public shouldAlwaysRevert;

  constructor(uint256 _maxAmount) {
    maxAmount = _maxAmount;
  }

  function setMaxAmount(uint256 _maxAmount) external {
    maxAmount = _maxAmount;
  }

  function setAllowed(address _receiver, bool _isAllowed) external {
    isAllowed[_receiver] = _isAllowed;
  }

  function setShouldAlwaysRevert(bool _shouldRevert) external {
    shouldAlwaysRevert = _shouldRevert;
  }

  function beforeMint(address, address receiver, uint256 amount) external view {
    if (shouldAlwaysRevert) {
      revert("MockMintHook: always revert");
    }
    if (amount > maxAmount) {
      revert MockMintHook__AmountTooHigh(amount, maxAmount);
    }
    if (!isAllowed[receiver]) {
      revert MockMintHook__ReceiverNotAllowed(receiver);
    }
  }
}
