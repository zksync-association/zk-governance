// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

contract Constants {
  uint256 constant VOTES_PER_SEAT = 1e18;
  uint256 constant MAX_MEMBER_COUNT = 20;
  uint48 constant VOTING_DELAY = 1 days;
  uint32 constant VOTING_PERIOD = 3 days;
  uint256 constant MAX_VETO_THRESHOLD = 1e30;
  uint48 constant VOTING_PERIOD_EXTENSION = 2 days;
  uint16 constant VOTING_PERIOD_EXTENSION_THRESHOLD_PCT = 50;

  string constant PROPOSAL_DESCRIPTION = "A protocol upgrade";
}
