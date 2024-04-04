// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/Checkpoints.sol";

//
abstract contract SettableFixedQuorum is Governor {
  using Checkpoints for Checkpoints.Trace224;

  /// @notice A history of quorum values for a given timestamp.
  Checkpoints.Trace224 internal _quorumCheckpoints;

  /// @param _initialQuorum The number of total votes needed to pass a proposal.
  constructor(uint224 _initialQuorum) {
    _setQuorum(_initialQuorum);
  }

  /// @notice A function to set quorum for the current block timestamp. Proposals created after this timestamp will be
  /// subject to the new quorum.
  /// @param _amount The new quorum threshold.
  function setQuorum(uint224 _amount) external onlyGovernance {
    _setQuorum(_amount);
  }

  /// @notice A function to get the quorum threshold for a given timestamp.
  /// @param _voteStart The timestamp of when voting starts for a given proposal.
  function quorum(uint256 _voteStart) public view override returns (uint256) {
    return _quorumCheckpoints.upperLookup(SafeCast.toUint32(_voteStart));
  }

  /// @notice A function to set quorum for the current block timestamp.
  /// @param _amount The quorum amount to checkpoint.
  function _setQuorum(uint224 _amount) internal {
    _quorumCheckpoints.push(SafeCast.toUint32(block.timestamp), _amount);
  }
}
