// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";

contract ZkProtocolUpgradeCouncilGovernorTest is Test {
  uint256 constant MEMBER_COUNT = 8;
  uint256 constant VOTES_PER_SEAT = 1e18;
  uint48 constant VOTING_DELAY = 1 days;
  uint32 constant VOTING_PERIOD = 3 days;

  // With eight seats, 12% of the supply is less than one seat and 50% is exactly four seats.
  uint256 constant ONE_SEAT_PCT = 12;
  uint256 constant FOUR_SEATS_PCT = 50;

  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;

  CouncilERC20 councilToken;
  ZkProtocolUpgradeCouncilGovernor governor;
  address[] members;

  function setUp() public virtual {
    vm.warp(1_700_000_000);
    for (uint256 _i = 0; _i < MEMBER_COUNT; _i++) {
      members.push(makeAddr(string.concat("Member ", vm.toString(_i))));
    }
  }

  // Deploys a council of `MEMBER_COUNT` members holding one seat of `_votesPerSeat` each, and its governor.
  function _deployCouncil(uint256 _votesPerSeat, uint256 _quorumPct, uint256 _superQuorumPct) internal {
    councilToken = new CouncilERC20("Council Seat", "SEAT", address(this), _votesPerSeat);
    for (uint256 _i = 0; _i < MEMBER_COUNT; _i++) {
      councilToken.mint(members[_i], _votesPerSeat);
    }
    governor = new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor",
      IERC5805(address(councilToken)),
      IGovernor(address(0)),
      makeAddr("Governor Admin"),
      BasicCouncilGovernor.InitialCouncilParams({
        initialVotingDelay: VOTING_DELAY,
        initialVotingPeriod: VOTING_PERIOD,
        initialProposalThreshold: _votesPerSeat,
        initialQuorumFraction: _quorumPct,
        initialSuperQuorumFraction: _superQuorumPct
      })
    );
    // Seats count from the timestamp after they are minted, so move past it before any proposal is created.
    vm.warp(block.timestamp + 1);
  }

  // Proposes from the first member and moves to the start of voting.
  function _proposeAndOpenVoting() internal returns (uint256 _proposalId) {
    address[] memory _targets = new address[](1);
    _targets[0] = makeAddr("Target");
    uint256[] memory _values = new uint256[](1);
    bytes[] memory _calldatas = new bytes[](1);
    vm.prank(members[0]);
    _proposalId = governor.propose(_targets, _values, _calldatas, "A protocol upgrade");
    vm.warp(governor.proposalSnapshot(_proposalId) + 1);
  }

  function _castVote(uint256 _proposalId, uint256 _memberIndex, uint8 _support) internal {
    vm.prank(members[_memberIndex]);
    governor.castVote(_proposalId, _support);
  }

  function _jumpPastTheProposalDeadline(uint256 _proposalId) internal {
    vm.warp(governor.proposalDeadline(_proposalId) + 1);
  }

  function _assertState(uint256 _proposalId, IGovernor.ProposalState _expectedState) internal {
    assertEq(uint8(governor.state(_proposalId)), uint8(_expectedState));
  }
}

contract State is ZkProtocolUpgradeCouncilGovernorTest {
  function test_ReturnsSucceededAsSoonAsOneMemberVotesForWhenOneSeatMeetsQuorumAndSuperQuorum() public {
    _deployCouncil(VOTES_PER_SEAT, ONE_SEAT_PCT, ONE_SEAT_PCT);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, 0, FOR);

    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_ReturnsSucceededWhenEveryOtherMemberVotesAgainstOrAbstains(uint256 _supportBits) public {
    // A four-seat super-quorum keeps voting open after the first FOR vote, so the other members can still vote.
    _deployCouncil(VOTES_PER_SEAT, ONE_SEAT_PCT, FOUR_SEATS_PCT);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, 0, FOR);
    for (uint256 _i = 1; _i < MEMBER_COUNT; _i++) {
      // Each bit of `_supportBits` picks whether that member votes AGAINST or ABSTAIN.
      _castVote(_proposalId, _i, (_supportBits >> _i) & 1 == 0 ? AGAINST : ABSTAIN);
    }
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }

  function test_ReturnsActiveUntilTheDeadlineWhenForVotesMeetQuorumButNotSuperQuorum() public {
    _deployCouncil(VOTES_PER_SEAT, ONE_SEAT_PCT, FOUR_SEATS_PCT);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, 0, FOR);
    _assertState(_proposalId, IGovernor.ProposalState.Active);

    _jumpPastTheProposalDeadline(_proposalId);
    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }

  function test_ReturnsDefeatedWhenForVotesAreBelowQuorumEvenIfAbstainVotesWouldMeetIt() public {
    _deployCouncil(VOTES_PER_SEAT, FOUR_SEATS_PCT, FOUR_SEATS_PCT);
    uint256 _proposalId = _proposeAndOpenVoting();

    // Three FOR seats are one short of the four-seat quorum; counting the five ABSTAIN seats would meet it.
    for (uint256 _i = 0; _i < 3; _i++) {
      _castVote(_proposalId, _i, FOR);
    }
    for (uint256 _i = 3; _i < MEMBER_COUNT; _i++) {
      _castVote(_proposalId, _i, ABSTAIN);
    }
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }

  function test_ReturnsDefeatedWhenNoMemberVotesForAndQuorumRoundsToZero() public {
    // Seats of one base unit: 12% of a supply of 8 rounds down to a quorum of 0.
    _deployCouncil(1, ONE_SEAT_PCT, ONE_SEAT_PCT);
    uint256 _proposalId = _proposeAndOpenVoting();
    assertEq(governor.quorum(governor.proposalSnapshot(_proposalId)), 0);

    _castVote(_proposalId, 0, ABSTAIN);
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }
}
