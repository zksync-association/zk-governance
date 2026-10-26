// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";

contract ZkProtocolUpgradeCouncilGovernorTest is Test {
  uint256 constant VOTES_PER_SEAT = 1e18;
  uint256 constant MAX_MEMBER_COUNT = 20;
  uint48 constant VOTING_DELAY = 1 days;
  uint32 constant VOTING_PERIOD = 3 days;

  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;

  CouncilERC20 councilToken;
  ZkProtocolUpgradeCouncilGovernor governor;
  address governorAdmin = makeAddr("Governor Admin");
  address[] members;

  function setUp() public virtual {
    vm.warp(1_700_000_000);
    councilToken = new CouncilERC20("Council Seat", "SEAT", address(this), VOTES_PER_SEAT);
    governor = new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(0)), governorAdmin, _councilParams(0, 0)
    );
  }

  function _councilParams(uint256 _quorumFraction, uint256 _superQuorumFraction)
    internal
    pure
    returns (BasicCouncilGovernor.InitialCouncilParams memory)
  {
    return BasicCouncilGovernor.InitialCouncilParams({
      initialVotingDelay: VOTING_DELAY,
      initialVotingPeriod: VOTING_PERIOD,
      initialProposalThreshold: VOTES_PER_SEAT,
      initialQuorumFraction: _quorumFraction,
      initialSuperQuorumFraction: _superQuorumFraction
    });
  }

  // Mints a full seat to each of `_memberCount` new members.
  function _seatMembers(uint256 _memberCount) internal {
    for (uint256 _i = 0; _i < _memberCount; _i++) {
      address _member = makeAddr(string.concat("Member ", vm.toString(_i)));
      members.push(_member);
      councilToken.mint(_member, VOTES_PER_SEAT);
    }
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

  function _castVote(uint256 _proposalId, address _voter, uint8 _support) internal {
    vm.prank(_voter);
    governor.castVote(_proposalId, _support);
  }

  // Each bit of `_supportBits` picks whether a member votes AGAINST (0) or ABSTAIN (1).
  function _againstOrAbstain(uint256 _supportBits, uint256 _memberIndex) internal pure returns (uint8) {
    return (_supportBits >> _memberIndex) & 1 == 0 ? AGAINST : ABSTAIN;
  }

  function _jumpPastTheProposalDeadline(uint256 _proposalId) internal {
    vm.warp(governor.proposalDeadline(_proposalId) + 1);
  }

  function _assertState(uint256 _proposalId, IGovernor.ProposalState _expectedState) internal {
    assertEq(uint8(governor.state(_proposalId)), uint8(_expectedState));
  }
}

contract Constructor is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_SetsVotesPerSeatToTheCouncilTokensMaximumPerMember(uint256 _votesPerSeat) public {
    _votesPerSeat = bound(_votesPerSeat, 1, type(uint208).max);
    CouncilERC20 _councilToken = new CouncilERC20("Council Seat", "SEAT", address(this), _votesPerSeat);

    ZkProtocolUpgradeCouncilGovernor _governor = new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", _councilToken, IGovernor(address(0)), governorAdmin, _councilParams(0, 0)
    );

    assertEq(_governor.VOTES_PER_SEAT(), _votesPerSeat);
  }

  function testFuzz_RevertIf_AQuorumFractionIsConfigured(uint256 _quorumFraction) public {
    _quorumFraction = bound(_quorumFraction, 1, 100);
    BasicCouncilGovernor.InitialCouncilParams memory _params = _councilParams(_quorumFraction, _quorumFraction);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled.selector);
    new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(0)), governorAdmin, _params
    );
  }

  function testFuzz_RevertIf_OnlyASuperQuorumFractionIsConfigured(uint256 _superQuorumFraction) public {
    _superQuorumFraction = bound(_superQuorumFraction, 1, 100);
    BasicCouncilGovernor.InitialCouncilParams memory _params = _councilParams(0, _superQuorumFraction);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled.selector);
    new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(0)), governorAdmin, _params
    );
  }
}

contract CountingMode is ZkProtocolUpgradeCouncilGovernorTest {
  function test_ReportsThatOnlyForVotesCountTowardQuorum() public {
    assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for");
  }
}

contract Quorum is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_IsOneSeatHoweverManySeatsExist(uint256 _memberCount, uint256 _timepoint) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));

    assertEq(governor.quorum(_timepoint), VOTES_PER_SEAT);
    assertEq(governor.superQuorum(_timepoint), VOTES_PER_SEAT);
  }
}

contract State is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_ReturnsSucceededAsSoonAsOneMemberVotesForHoweverManySeatsExist(uint256 _memberCount) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, members[0], FOR);

    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_ReturnsSucceededWhenEveryOtherMemberHasVotedAgainstOrAbstained(
    uint256 _memberCount,
    uint256 _supportBits
  ) public {
    _seatMembers(bound(_memberCount, 2, MAX_MEMBER_COUNT));
    uint256 _proposalId = _proposeAndOpenVoting();

    // The other members vote first, since the first FOR seat ends voting.
    for (uint256 _i = 1; _i < members.length; _i++) {
      _castVote(_proposalId, members[_i], _againstOrAbstain(_supportBits, _i));
    }
    _castVote(_proposalId, members[0], FOR);

    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_ReturnsActiveUntilTheDeadlineWhenNoMemberVotesFor(uint256 _memberCount, uint256 _supportBits)
    public
  {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _proposeAndOpenVoting();

    for (uint256 _i = 0; _i < members.length; _i++) {
      _castVote(_proposalId, members[_i], _againstOrAbstain(_supportBits, _i));
    }

    _assertState(_proposalId, IGovernor.ProposalState.Active);
  }

  function testFuzz_ReturnsDefeatedAfterTheDeadlineWhenNoMemberVotesFor(uint256 _memberCount, uint256 _supportBits)
    public
  {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _proposeAndOpenVoting();

    for (uint256 _i = 0; _i < members.length; _i++) {
      _castVote(_proposalId, members[_i], _againstOrAbstain(_supportBits, _i));
    }
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_ReturnsDefeatedWhenTheOnlyForVoteIsLessThanOneSeat(uint256 _partialSeatVotes) public {
    _partialSeatVotes = bound(_partialSeatVotes, 1, VOTES_PER_SEAT - 1);
    _seatMembers(1);
    address _partialMember = makeAddr("Partial Member");
    councilToken.mint(_partialMember, _partialSeatVotes);
    vm.warp(block.timestamp + 1);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, _partialMember, FOR);
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }
}

contract UpdateQuorumNumerator is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_CalledByTheGovernorAdmin(uint256 _newQuorumNumerator) public {
    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled.selector);
    vm.prank(governorAdmin);
    governor.updateQuorumNumerator(_newQuorumNumerator);
  }
}

contract UpdateSuperQuorumNumerator is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_CalledByTheGovernorAdmin(uint256 _newSuperQuorumNumerator) public {
    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled.selector);
    vm.prank(governorAdmin);
    governor.updateSuperQuorumNumerator(_newSuperQuorumNumerator);
  }
}
