// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {
  GovernorCompatibilityBravo
} from "@openzeppelin/contracts/governance/compatibility/GovernorCompatibilityBravo.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {Constants} from "test/utils/Constants.sol";

/// @notice Tests the Supermajority Governor. A proposal succeeds only if its FOR votes alone reach the 1.26B quorum,
/// with ABSTAIN votes not counting toward it, and it has more FOR than AGAINST votes.
contract ZKSupermajorityTest is Test, Constants {
  ERC20VotesFake token;
  TimelockController timelock;
  ZkProtocolGovernor governor;

  address forVoter = makeAddr("For Voter");
  address againstVoter = makeAddr("Against Voter");
  address abstainVoter = makeAddr("Abstain Voter");
  address splitVoter = makeAddr("Split Voter");

  function setUp() public virtual {
    token = new ERC20VotesFake();
    // These tests only count votes, so the proposal threshold is zero and the timelock grants the governor no roles.
    timelock = new TimelockController(1 days, new address[](0), new address[](0), address(this));
    governor = new ZkProtocolGovernor(
      "ZKsync Supermajority Governor", IVotes(address(token)), timelock, 1 days, 7 days, 0, SUPERMAJORITY_QUORUM, 3 days
    );
  }

  function _mintAndSelfDelegateVotes(address _voter, uint256 _amount) internal {
    token.mint(_voter, _amount);
    vm.prank(_voter);
    token.delegate(_voter);
  }

  function _propose() internal returns (uint256 _proposalId) {
    address[] memory _targets = new address[](1);
    _targets[0] = address(timelock);
    uint256[] memory _values = new uint256[](1);
    bytes[] memory _calldatas = new bytes[](1);
    _proposalId = governor.propose(_targets, _values, _calldatas, "Override a veto");
  }

  // Skips voters with no votes at the proposal's snapshot, since the governor rejects a vote with no weight and tests
  // may leave a side at zero.
  function _castVoteIfHasVotes(uint256 _proposalId, address _voter, uint8 _support) internal {
    if (token.getPastVotes(_voter, governor.proposalSnapshot(_proposalId)) == 0) {
      return;
    }
    vm.prank(_voter);
    governor.castVote(_proposalId, _support);
  }

  /// @notice Proposes, has `splitVoter` split its weight across AGAINST, FOR and ABSTAIN with a fractional vote, and
  /// returns the proposal's state after voting ends.
  function _stateAfterSplitVote(uint128 _forVotes, uint128 _againstVotes, uint128 _abstainVotes)
    internal
    returns (IGovernor.ProposalState)
  {
    _mintAndSelfDelegateVotes(splitVoter, uint256(_forVotes) + _againstVotes + _abstainVotes);
    vm.warp(block.timestamp + 1);

    uint256 _proposalId = _propose();
    vm.warp(governor.proposalSnapshot(_proposalId) + 1);
    vm.prank(splitVoter);
    governor.castVoteWithReasonAndParams(
      _proposalId,
      uint8(GovernorCompatibilityBravo.VoteType.For),
      "",
      abi.encodePacked(_againstVotes, _forVotes, _abstainVotes)
    );
    vm.warp(governor.proposalDeadline(_proposalId) + 1);
    return governor.state(_proposalId);
  }

  /// @notice Proposes, casts each voter's full weight and returns the proposal's state after voting ends.
  function _stateAfterVoting(uint256 _forVotes, uint256 _againstVotes, uint256 _abstainVotes)
    internal
    returns (IGovernor.ProposalState)
  {
    _mintAndSelfDelegateVotes(forVoter, _forVotes);
    _mintAndSelfDelegateVotes(againstVoter, _againstVotes);
    _mintAndSelfDelegateVotes(abstainVoter, _abstainVotes);
    vm.warp(block.timestamp + 1);

    uint256 _proposalId = _propose();
    vm.warp(governor.proposalSnapshot(_proposalId) + 1);
    _castVoteIfHasVotes(_proposalId, forVoter, uint8(GovernorCompatibilityBravo.VoteType.For));
    _castVoteIfHasVotes(_proposalId, againstVoter, uint8(GovernorCompatibilityBravo.VoteType.Against));
    _castVoteIfHasVotes(_proposalId, abstainVoter, uint8(GovernorCompatibilityBravo.VoteType.Abstain));
    vm.warp(governor.proposalDeadline(_proposalId) + 1);
    return governor.state(_proposalId);
  }
}

contract State is ZKSupermajorityTest {
  function testFuzz_SucceedsWhenForVotesMeetQuorumAndExceedAgainstVotes(
    uint256 _forVotes,
    uint256 _againstVotes,
    uint256 _abstainVotes
  ) public {
    _forVotes = bound(_forVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES);
    _againstVotes = bound(_againstVotes, 0, _forVotes - 1);
    _abstainVotes = bound(_abstainVotes, 0, MAX_SUPERMAJORITY_VOTES);

    assertEq(
      uint8(_stateAfterVoting(_forVotes, _againstVotes, _abstainVotes)), uint8(IGovernor.ProposalState.Succeeded)
    );
  }

  function testFuzz_DefeatedWhenForVotesAreBelowQuorumEvenIfAbstainVotesMeetQuorum(
    uint256 _forVotes,
    uint256 _abstainVotes
  ) public {
    _forVotes = bound(_forVotes, 1, SUPERMAJORITY_QUORUM - 1);
    _abstainVotes = bound(_abstainVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES);

    assertEq(uint8(_stateAfterVoting(_forVotes, 0, _abstainVotes)), uint8(IGovernor.ProposalState.Defeated));
  }

  function testFuzz_DefeatedWhenForVotesMeetQuorumButDoNotExceedAgainstVotes(uint256 _forVotes, uint256 _againstVotes)
    public
  {
    _forVotes = bound(_forVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES);
    _againstVotes = bound(_againstVotes, _forVotes, MAX_SUPERMAJORITY_VOTES);

    assertEq(uint8(_stateAfterVoting(_forVotes, _againstVotes, 0)), uint8(IGovernor.ProposalState.Defeated));
  }

  function testFuzz_SucceedsWhenForVotesMeetQuorumAndExceedAgainstVotesInOneFractionalVote(
    uint128 _forVotes,
    uint128 _againstVotes,
    uint128 _abstainVotes
  ) public {
    _forVotes = uint128(bound(_forVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES));
    _againstVotes = uint128(bound(_againstVotes, 0, _forVotes - 1));
    _abstainVotes = uint128(bound(_abstainVotes, 0, MAX_SUPERMAJORITY_VOTES));

    assertEq(
      uint8(_stateAfterSplitVote(_forVotes, _againstVotes, _abstainVotes)), uint8(IGovernor.ProposalState.Succeeded)
    );
  }

  function testFuzz_DefeatedWhenForVotesMeetQuorumButDoNotExceedAgainstVotesInOneFractionalVote(
    uint128 _forVotes,
    uint128 _againstVotes
  ) public {
    _forVotes = uint128(bound(_forVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES));
    _againstVotes = uint128(bound(_againstVotes, _forVotes, MAX_SUPERMAJORITY_VOTES));

    assertEq(uint8(_stateAfterSplitVote(_forVotes, _againstVotes, 0)), uint8(IGovernor.ProposalState.Defeated));
  }

  function testFuzz_DefeatedWhenForVotesAreBelowQuorumEvenIfAbstainVotesMeetQuorumInOneFractionalVote(
    uint128 _forVotes,
    uint128 _abstainVotes
  ) public {
    _forVotes = uint128(bound(_forVotes, 1, SUPERMAJORITY_QUORUM - 1));
    _abstainVotes = uint128(bound(_abstainVotes, SUPERMAJORITY_QUORUM, MAX_SUPERMAJORITY_VOTES));

    assertEq(uint8(_stateAfterSplitVote(_forVotes, 0, _abstainVotes)), uint8(IGovernor.ProposalState.Defeated));
  }
}
