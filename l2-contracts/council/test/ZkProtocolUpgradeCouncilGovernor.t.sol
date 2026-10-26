// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";
import {FakeCouncilVetoGovernor} from "test/fakes/FakeCouncilVetoGovernor.sol";

contract ZkProtocolUpgradeCouncilGovernorTest is Test {
  uint256 constant VOTES_PER_SEAT = 1e18;
  uint256 constant MAX_MEMBER_COUNT = 20;
  uint48 constant VOTING_DELAY = 1 days;
  uint32 constant VOTING_PERIOD = 3 days;

  uint8 constant AGAINST = 0;
  uint8 constant FOR = 1;
  uint8 constant ABSTAIN = 2;

  string constant PROPOSAL_DESCRIPTION = "A protocol upgrade";

  CouncilERC20 councilToken;
  FakeCouncilVetoGovernor vetoGovernor;
  ZkProtocolUpgradeCouncilGovernor governor;
  address governorAdmin = makeAddr("Governor Admin");
  address proposalTarget = makeAddr("Target");
  address[] members;

  function setUp() public virtual {
    vm.warp(1_700_000_000);
    councilToken = new CouncilERC20("Council Seat", "SEAT", address(this), VOTES_PER_SEAT);
    vetoGovernor = new FakeCouncilVetoGovernor();
    governor = new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(vetoGovernor)), governorAdmin, _councilParams(0, 0)
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
    for (uint256 _i = 0; _i < _memberCount; _i += 1) {
      address _member = makeAddr(string.concat("Member ", vm.toString(_i)));
      members.push(_member);
      councilToken.mint(_member, VOTES_PER_SEAT);
    }
    // Seats count from the timestamp after they are minted, so move past it before any proposal is created.
    vm.warp(block.timestamp + 1);
  }

  // The actions of the proposal every test submits: one empty call to `proposalTarget`.
  function _proposalActions()
    internal
    view
    returns (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas)
  {
    _targets = new address[](1);
    _targets[0] = proposalTarget;
    _values = new uint256[](1);
    _calldatas = new bytes[](1);
  }

  // Mints less than a full seat to a new member.
  function _mintPartialSeat(string memory _name, uint256 _votes) internal returns (address _member) {
    _member = makeAddr(_name);
    councilToken.mint(_member, _votes);
    vm.warp(block.timestamp + 1);
  }

  // Excludes the addresses below 0x10000, where EraVM keeps its system contracts and precompiles.
  function _assumeNotASystemAddress(address _account) internal pure {
    vm.assume(uint160(_account) > 0xFFFF);
  }

  // Proposes from the first member and moves to the start of voting.
  function _proposeAndOpenVoting() internal returns (uint256 _proposalId) {
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) = _proposalActions();
    vm.prank(members[0]);
    _proposalId = governor.propose(_targets, _values, _calldatas, PROPOSAL_DESCRIPTION);
    vm.warp(governor.proposalSnapshot(_proposalId) + 1);
  }

  // Passes the proposal with one FOR seat and queues it, which submits it to the veto governor.
  function _passAndQueue() internal returns (uint256 _proposalId) {
    _proposalId = _proposeAndOpenVoting();
    _castVote(_proposalId, members[0], FOR);
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) = _proposalActions();
    governor.queue(_targets, _values, _calldatas, keccak256(bytes(PROPOSAL_DESCRIPTION)));
  }

  function _castVote(uint256 _proposalId, address _voter, uint8 _support) internal {
    vm.prank(_voter);
    governor.castVote(_proposalId, _support);
  }

  // Each bit of `_supportBits` picks whether a member votes AGAINST (0) or ABSTAIN (1).
  function _againstOrAbstain(uint256 _supportBits, uint256 _memberIndex) internal pure returns (uint8) {
    if ((_supportBits >> _memberIndex) & 1 == 0) {
      return AGAINST;
    }
    return ABSTAIN;
  }

  function _jumpPastTheProposalDeadline(uint256 _proposalId) internal {
    vm.warp(governor.proposalDeadline(_proposalId) + 1);
  }

  function _assertState(uint256 _proposalId, IGovernor.ProposalState _expectedState) internal view {
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
    BasicCouncilGovernor.InitialCouncilParams memory _params = _councilParams(_quorumFraction, 0);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor__QuorumFractionDisabled.selector);
    new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(0)), governorAdmin, _params
    );
  }

  function testFuzz_RevertIf_ASuperQuorumFractionIsConfigured(uint256 _superQuorumFraction) public {
    _superQuorumFraction = bound(_superQuorumFraction, 1, 100);
    BasicCouncilGovernor.InitialCouncilParams memory _params = _councilParams(0, _superQuorumFraction);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor__QuorumFractionDisabled.selector);
    new ZkProtocolUpgradeCouncilGovernor(
      "Council Governor", councilToken, IGovernor(address(0)), governorAdmin, _params
    );
  }
}

contract CountingMode is ZkProtocolUpgradeCouncilGovernorTest {
  function test_ReportsThatOnlyForVotesCountTowardQuorum() public view {
    assertEq(governor.COUNTING_MODE(), "support=bravo&quorum=for");
  }
}

contract Quorum is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_IsOneSeatHoweverManySeatsExist(uint256 _memberCount, uint256 _timepoint) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));

    assertEq(governor.quorum(_timepoint), VOTES_PER_SEAT);
  }
}

contract SuperQuorum is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_IsOneSeatHoweverManySeatsExist(uint256 _memberCount, uint256 _timepoint) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));

    assertEq(governor.superQuorum(_timepoint), VOTES_PER_SEAT);
  }
}

contract Propose is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_TheProposerHoldsLessThanOneSeat(uint256 _partialSeatVotes) public {
    _partialSeatVotes = bound(_partialSeatVotes, 0, VOTES_PER_SEAT - 1);
    _seatMembers(1);
    address _proposer = _mintPartialSeat("Partial Member", _partialSeatVotes);
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) = _proposalActions();

    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernor.GovernorInsufficientProposerVotes.selector, _proposer, _partialSeatVotes, VOTES_PER_SEAT
      )
    );
    vm.prank(_proposer);
    governor.propose(_targets, _values, _calldatas, PROPOSAL_DESCRIPTION);
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
    for (uint256 _i = 1; _i < members.length; _i += 1) {
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

    for (uint256 _i = 0; _i < members.length; _i += 1) {
      _castVote(_proposalId, members[_i], _againstOrAbstain(_supportBits, _i));
    }

    vm.warp(governor.proposalDeadline(_proposalId));
    _assertState(_proposalId, IGovernor.ProposalState.Active);
  }

  function testFuzz_ReturnsDefeatedAfterTheDeadlineWhenNoMemberVotesFor(uint256 _memberCount, uint256 _supportBits)
    public
  {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _proposeAndOpenVoting();

    for (uint256 _i = 0; _i < members.length; _i += 1) {
      _castVote(_proposalId, members[_i], _againstOrAbstain(_supportBits, _i));
    }
    _jumpPastTheProposalDeadline(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_ReturnsActiveThenDefeatedWhenTheOnlyForVoteIsLessThanOneSeat(uint256 _partialSeatVotes) public {
    _partialSeatVotes = bound(_partialSeatVotes, 1, VOTES_PER_SEAT - 1);
    _seatMembers(1);
    address _partialMember = _mintPartialSeat("Partial Member", _partialSeatVotes);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, _partialMember, FOR);
    _assertState(_proposalId, IGovernor.ProposalState.Active);

    _jumpPastTheProposalDeadline(_proposalId);
    _assertState(_proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_ReturnsSucceededAsSoonAsPartialForVotesAddUpToOneSeat(uint256 _firstPartialSeatVotes) public {
    _firstPartialSeatVotes = bound(_firstPartialSeatVotes, 1, VOTES_PER_SEAT - 1);
    _seatMembers(1);
    address _firstPartialMember = _mintPartialSeat("First Partial Member", _firstPartialSeatVotes);
    address _secondPartialMember = _mintPartialSeat("Second Partial Member", VOTES_PER_SEAT - _firstPartialSeatVotes);
    uint256 _proposalId = _proposeAndOpenVoting();

    _castVote(_proposalId, _firstPartialMember, FOR);
    _castVote(_proposalId, _secondPartialMember, FOR);

    _assertState(_proposalId, IGovernor.ProposalState.Succeeded);
  }
}

contract Queue is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_SubmitsASucceededProposalToTheVetoGovernor(uint256 _memberCount) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));

    // Queued while its voting period is still running, since the first FOR seat already passed it.
    uint256 _proposalId = _passAndQueue();

    // The veto governor received the same actions and description, so it identifies the proposal by the same ID.
    assertTrue(vetoGovernor.isSubmitted(_proposalId));
    assertEq(governor.proposalEta(_proposalId), vetoGovernor.PROPOSAL_DEADLINE());
    _assertState(_proposalId, IGovernor.ProposalState.Queued);
  }

  function testFuzz_ReportsCanceledOnceTheVetoGovernorDefeatsTheProposal(uint256 _memberCount) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _passAndQueue();

    vetoGovernor.defeat(_proposalId);

    _assertState(_proposalId, IGovernor.ProposalState.Canceled);
  }
}

contract CastVote is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_VotingAfterTheFirstForSeatPassedTheProposal(uint256 _memberCount, uint8 _support) public {
    _seatMembers(bound(_memberCount, 2, MAX_MEMBER_COUNT));
    _support = uint8(bound(_support, AGAINST, ABSTAIN));
    uint256 _proposalId = _proposeAndOpenVoting();
    _castVote(_proposalId, members[0], FOR);

    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernor.GovernorUnexpectedProposalState.selector,
        _proposalId,
        IGovernor.ProposalState.Succeeded,
        bytes32(1 << uint8(IGovernor.ProposalState.Active))
      )
    );
    _castVote(_proposalId, members[1], _support);
  }
}

contract Execute is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_ExecutesAQueuedProposalThroughTheVetoGovernor(uint256 _memberCount) public {
    _seatMembers(bound(_memberCount, 1, MAX_MEMBER_COUNT));
    uint256 _proposalId = _passAndQueue();
    vetoGovernor.succeed(_proposalId);
    (address[] memory _targets, uint256[] memory _values, bytes[] memory _calldatas) = _proposalActions();

    governor.execute(_targets, _values, _calldatas, keccak256(bytes(PROPOSAL_DESCRIPTION)));

    assertEq(uint8(vetoGovernor.state(_proposalId)), uint8(IGovernor.ProposalState.Executed));
    _assertState(_proposalId, IGovernor.ProposalState.Executed);
  }
}

contract UpdateQuorumNumerator is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_TheAdminSetsANonZeroQuorumFraction(uint256 _newQuorumNumerator) public {
    _newQuorumNumerator = bound(_newQuorumNumerator, 1, type(uint256).max);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor__QuorumFractionDisabled.selector);
    vm.prank(governorAdmin);
    governor.updateQuorumNumerator(_newQuorumNumerator);
  }

  function test_LetsTheAdminSetAZeroQuorumFractionWithoutRecordingIt() public {
    vm.recordLogs();
    vm.prank(governorAdmin);
    governor.updateQuorumNumerator(0);

    assertEq(vm.getRecordedLogs().length, 0);

    assertEq(governor.quorumNumerator(), 0);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheGovernorAdmin(address _caller) public {
    _assumeNotASystemAddress(_caller);
    vm.assume(_caller != governorAdmin);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
    vm.prank(_caller);
    governor.updateQuorumNumerator(0);
  }
}

contract UpdateSuperQuorumNumerator is ZkProtocolUpgradeCouncilGovernorTest {
  function testFuzz_RevertIf_TheAdminSetsANonZeroSuperQuorumFraction(uint256 _newSuperQuorumNumerator) public {
    _newSuperQuorumNumerator = bound(_newSuperQuorumNumerator, 1, type(uint256).max);

    vm.expectRevert(ZkProtocolUpgradeCouncilGovernor.ZkProtocolUpgradeCouncilGovernor__QuorumFractionDisabled.selector);
    vm.prank(governorAdmin);
    governor.updateSuperQuorumNumerator(_newSuperQuorumNumerator);
  }

  function test_LetsTheAdminSetAZeroSuperQuorumFractionWithoutRecordingIt() public {
    vm.recordLogs();
    vm.prank(governorAdmin);
    governor.updateSuperQuorumNumerator(0);

    assertEq(vm.getRecordedLogs().length, 0);

    assertEq(governor.superQuorumNumerator(), 0);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheGovernorAdmin(address _caller) public {
    _assumeNotASystemAddress(_caller);
    vm.assume(_caller != governorAdmin);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
    vm.prank(_caller);
    governor.updateSuperQuorumNumerator(0);
  }
}
