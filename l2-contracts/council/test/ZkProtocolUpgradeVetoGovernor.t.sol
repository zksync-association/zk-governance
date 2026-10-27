// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {BasicCouncilVetoGovernor} from "council-governance/BasicCouncilVetoGovernor.sol";
import {ZkProtocolUpgradeVetoGovernor} from "src/ZkProtocolUpgradeVetoGovernor.sol";
import {FakeVotesToken} from "test/fakes/FakeVotesToken.sol";
import {Constants} from "test/utils/Constants.sol";
import {TestHelpers} from "test/utils/TestHelpers.sol";

contract ZkProtocolUpgradeVetoGovernorTest is TestHelpers, Constants {
  FakeVotesToken token;
  address council = makeAddr("Council");
  address governorAdmin = makeAddr("Governor Admin");
  address voter = makeAddr("Voter");

  function setUp() public virtual {
    // Starts at an arbitrary but realistic Unix time (Nov 2023); no test depends on the exact value.
    vm.warp(1_700_000_000);
    token = new FakeVotesToken();
  }

  function _constructorParams(uint256 _vetoThresholdNumerator)
    internal
    returns (BasicCouncilVetoGovernor.ConstructorParams memory)
  {
    return BasicCouncilVetoGovernor.ConstructorParams({
      name: "Veto Governor",
      token: address(token),
      votingDelay: VOTING_DELAY,
      votingPeriod: VOTING_PERIOD,
      proposalThreshold: 0,
      vetoGuardian: makeAddr("Veto Guardian"),
      vetoOverrideRole: makeAddr("Veto Override Role"),
      vetoOverrideDuration: 14 days,
      votingPeriodExtension: VOTING_PERIOD_EXTENSION,
      votingPeriodExtensionThresholdPct: VOTING_PERIOD_EXTENSION_THRESHOLD_PCT,
      vetoThresholdNumerator: _vetoThresholdNumerator,
      timelock: TimelockController(payable(makeAddr("Timelock"))),
      governorAdmin: governorAdmin,
      council: council
    });
  }

  // Constrains fuzzed constructor params to those the base governor's constructor accepts.
  function _boundToValidConstructorParams(BasicCouncilVetoGovernor.ConstructorParams memory _params)
    internal
    view
    returns (BasicCouncilVetoGovernor.ConstructorParams memory)
  {
    // The token needs code, since the constructor reads its clock.
    _params.token = address(token);
    _params.vetoThresholdNumerator = 0;
    vm.assume(_params.governorAdmin != address(0));
    vm.assume(_params.votingPeriod != 0);
    _params.votingPeriodExtensionThresholdPct = uint16(_bound(_params.votingPeriodExtensionThresholdPct, 0, 100));
    return _params;
  }

  function _deployGovernorWithVetoThreshold(uint256 _vetoThreshold) internal returns (ZkProtocolUpgradeVetoGovernor) {
    return new ZkProtocolUpgradeVetoGovernor(_constructorParams(0), _vetoThreshold);
  }

  function _boundToValidVetoThreshold(uint256 _vetoThreshold) internal pure returns (uint256) {
    return _bound(_vetoThreshold, 1, MAX_VETO_THRESHOLD);
  }

  // The AGAINST votes at which the voting period is extended, as `GovernorExtendVetoPeriod` computes it.
  function _votingPeriodExtensionThreshold(uint256 _vetoThreshold) internal pure returns (uint256) {
    return _vetoThreshold * VOTING_PERIOD_EXTENSION_THRESHOLD_PCT / 100;
  }

  function _mintAndSelfDelegateVotes(address _account, uint256 _amount) internal {
    token.mint(_account, _amount);
    vm.prank(_account);
    token.delegate(_account);
    // Votes count from the next timestamp, so move past the delegation before any proposal is created.
    vm.warp(block.timestamp + 1);
  }

  function _proposeFromCouncil(ZkProtocolUpgradeVetoGovernor _governor) internal returns (uint256) {
    address[] memory _targets = new address[](1);
    _targets[0] = makeAddr("Target");
    uint256[] memory _values = new uint256[](1);
    bytes[] memory _calldatas = new bytes[](1);
    vm.prank(council);
    return _governor.propose(_targets, _values, _calldatas, PROPOSAL_DESCRIPTION);
  }

  function _castAgainstVoteOnceVotingOpens(ZkProtocolUpgradeVetoGovernor _governor, uint256 _proposalId) internal {
    vm.warp(_governor.proposalSnapshot(_proposalId) + 1);
    vm.prank(voter);
    _governor.castVote(_proposalId, uint8(GovernorCountingSimple.VoteType.Against));
  }

  function _jumpPastTheProposalDeadline(ZkProtocolUpgradeVetoGovernor _governor, uint256 _proposalId) internal {
    vm.warp(_governor.proposalDeadline(_proposalId) + 1);
  }

  function _setVetoThresholdAsAdmin(ZkProtocolUpgradeVetoGovernor _governor, uint256 _newVetoThreshold) internal {
    vm.prank(governorAdmin);
    _governor.setVetoThreshold(_newVetoThreshold);
  }

  function _assertState(
    ZkProtocolUpgradeVetoGovernor _governor,
    uint256 _proposalId,
    IGovernor.ProposalState _expectedState
  ) internal view {
    assertEq(uint8(_governor.state(_proposalId)), uint8(_expectedState));
  }
}

contract Constructor is ZkProtocolUpgradeVetoGovernorTest {
  function testFuzz_SetsAllConstructorParameters(
    BasicCouncilVetoGovernor.ConstructorParams memory _params,
    uint256 _vetoThreshold
  ) public {
    _params = _boundToValidConstructorParams(_params);
    _vetoThreshold = _boundToValidVetoThreshold(_vetoThreshold);

    ZkProtocolUpgradeVetoGovernor _governor = new ZkProtocolUpgradeVetoGovernor(_params, _vetoThreshold);

    assertEq(_governor.name(), _params.name);
    assertEq(address(_governor.token()), _params.token);
    assertEq(_governor.votingDelay(), _params.votingDelay);
    assertEq(_governor.votingPeriod(), _params.votingPeriod);
    assertEq(_governor.proposalThreshold(), _params.proposalThreshold);
    assertEq(_governor.vetoGuardian(), _params.vetoGuardian);
    assertEq(_governor.vetoOverrideRole(), _params.vetoOverrideRole);
    assertEq(_governor.vetoOverrideDuration(), _params.vetoOverrideDuration);
    assertEq(_governor.votingPeriodExtension(), _params.votingPeriodExtension);
    assertEq(_governor.minorVetoExtensionThresholdPct(), _params.votingPeriodExtensionThresholdPct);
    assertEq(address(_governor.timelock()), address(_params.timelock));
    assertEq(_governor.owner(), _params.governorAdmin);
    assertEq(_governor.COUNCIL(), _params.council);
    assertEq(_governor.vetoThresholdNumerator(), 0);
    assertEq(_governor.vetoThreshold(block.timestamp), _vetoThreshold);
  }

  function testFuzz_EmitsVetoThresholdSet(uint256 _vetoThreshold) public {
    _vetoThreshold = _boundToValidVetoThreshold(_vetoThreshold);

    vm.expectEmit();
    emit ZkProtocolUpgradeVetoGovernor.VetoThresholdSet(0, _vetoThreshold);
    _deployGovernorWithVetoThreshold(_vetoThreshold);
  }

  function testFuzz_RevertIf_TheInitialVetoThresholdIsZero(BasicCouncilVetoGovernor.ConstructorParams memory _params)
    public
  {
    _params = _boundToValidConstructorParams(_params);

    vm.expectRevert(ZkProtocolUpgradeVetoGovernor.ZkProtocolUpgradeVetoGovernor__InvalidVetoThreshold.selector);
    new ZkProtocolUpgradeVetoGovernor(_params, 0);
  }

  function testFuzz_RevertIf_TheVetoThresholdNumeratorIsNonZero(
    BasicCouncilVetoGovernor.ConstructorParams memory _params,
    uint256 _vetoThresholdNumerator,
    uint256 _vetoThreshold
  ) public {
    _params = _boundToValidConstructorParams(_params);
    _params.vetoThresholdNumerator = _bound(_vetoThresholdNumerator, 1, type(uint256).max);
    _vetoThreshold = _boundToValidVetoThreshold(_vetoThreshold);

    vm.expectRevert(ZkProtocolUpgradeVetoGovernor.ZkProtocolUpgradeVetoGovernor__VetoThresholdFractionDisabled.selector);
    new ZkProtocolUpgradeVetoGovernor(_params, _vetoThreshold);
  }
}

contract SetVetoThreshold is ZkProtocolUpgradeVetoGovernorTest {
  function testFuzz_SetsTheVetoThresholdFromTheCurrentTimepoint(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold,
    uint256 _elapsed
  ) public {
    _initialVetoThreshold = _boundToValidVetoThreshold(_initialVetoThreshold);
    _newVetoThreshold = _boundToValidVetoThreshold(_newVetoThreshold);
    _elapsed = _bound(_elapsed, 1, 365 days);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    uint256 _deployedAt = block.timestamp;
    vm.warp(block.timestamp + _elapsed);

    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);

    assertEq(_governor.vetoThreshold(block.timestamp), _newVetoThreshold);
    assertEq(_governor.vetoThreshold(block.timestamp - 1), _initialVetoThreshold);
    assertEq(_governor.vetoThreshold(_deployedAt), _initialVetoThreshold);
  }

  function testFuzz_EmitsVetoThresholdSet(uint256 _initialVetoThreshold, uint256 _newVetoThreshold) public {
    _initialVetoThreshold = _boundToValidVetoThreshold(_initialVetoThreshold);
    _newVetoThreshold = _boundToValidVetoThreshold(_newVetoThreshold);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);

    vm.expectEmit();
    emit ZkProtocolUpgradeVetoGovernor.VetoThresholdSet(_initialVetoThreshold, _newVetoThreshold);
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
  }

  function testFuzz_RevertIf_TheNewVetoThresholdIsZero(uint256 _initialVetoThreshold) public {
    ZkProtocolUpgradeVetoGovernor _governor =
      _deployGovernorWithVetoThreshold(_boundToValidVetoThreshold(_initialVetoThreshold));

    vm.expectRevert(ZkProtocolUpgradeVetoGovernor.ZkProtocolUpgradeVetoGovernor__InvalidVetoThreshold.selector);
    _setVetoThresholdAsAdmin(_governor, 0);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheGovernorAdmin(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold,
    address _caller
  ) public {
    _assumeNotASystemAddress(_caller);
    vm.assume(_caller != governorAdmin);
    ZkProtocolUpgradeVetoGovernor _governor =
      _deployGovernorWithVetoThreshold(_boundToValidVetoThreshold(_initialVetoThreshold));

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
    vm.prank(_caller);
    _governor.setVetoThreshold(_boundToValidVetoThreshold(_newVetoThreshold));
  }
}

contract State is ZkProtocolUpgradeVetoGovernorTest {
  function testFuzz_DefeatedWhenAgainstVotesReachTheVetoThreshold(uint256 _vetoThreshold, uint256 _againstVotes)
    public
  {
    _vetoThreshold = _boundToValidVetoThreshold(_vetoThreshold);
    _againstVotes = _bound(_againstVotes, _vetoThreshold, MAX_VETO_THRESHOLD);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_vetoThreshold);
    _mintAndSelfDelegateVotes(voter, _againstVotes);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_SucceededWhenAgainstVotesAreBelowTheVetoThreshold(uint256 _vetoThreshold, uint256 _againstVotes)
    public
  {
    _vetoThreshold = _bound(_vetoThreshold, 2, MAX_VETO_THRESHOLD);
    _againstVotes = _bound(_againstVotes, 1, _vetoThreshold - 1);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_vetoThreshold);
    _mintAndSelfDelegateVotes(voter, _againstVotes);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_UsesAVetoThresholdSetBeforeTheProposalSnapshot(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold
  ) public {
    // AGAINST votes equal to the new threshold veto the proposal only if the new, lower threshold applies.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 2, MAX_VETO_THRESHOLD);
    _newVetoThreshold = _bound(_newVetoThreshold, 1, _initialVetoThreshold - 1);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _newVetoThreshold);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    // The proposal is still pending, so its snapshot is after this change.
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_UsesAVetoThresholdSetAtTheProposalSnapshot(uint256 _initialVetoThreshold, uint256 _newVetoThreshold)
    public
  {
    // A change at the snapshot timepoint itself is still in force at the snapshot, so it applies to the proposal.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 2, MAX_VETO_THRESHOLD);
    _newVetoThreshold = _bound(_newVetoThreshold, 1, _initialVetoThreshold - 1);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _newVetoThreshold);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    vm.warp(_governor.proposalSnapshot(_proposalId));
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Defeated);
  }

  function testFuzz_UsesARaisedVetoThresholdSetBeforeTheProposalSnapshot(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold
  ) public {
    // AGAINST votes equal to the initial threshold fall short of the new, higher threshold, which applies.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 1, MAX_VETO_THRESHOLD - 1);
    _newVetoThreshold = _bound(_newVetoThreshold, _initialVetoThreshold + 1, MAX_VETO_THRESHOLD);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _initialVetoThreshold);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_IgnoresALoweredVetoThresholdSetAfterTheProposalSnapshot(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold
  ) public {
    // AGAINST votes equal to the new, lower threshold fall short of the initial threshold, which still applies.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 2, MAX_VETO_THRESHOLD);
    _newVetoThreshold = _bound(_newVetoThreshold, 1, _initialVetoThreshold - 1);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _newVetoThreshold);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    vm.warp(_governor.proposalSnapshot(_proposalId) + 1);
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Succeeded);
  }

  function testFuzz_KeepsTheVetoThresholdInForceAtTheProposalSnapshot(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold
  ) public {
    // AGAINST votes equal to the initial threshold veto the proposal only if the initial threshold still applies.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 1, MAX_VETO_THRESHOLD - 1);
    _newVetoThreshold = _bound(_newVetoThreshold, _initialVetoThreshold + 1, MAX_VETO_THRESHOLD);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _initialVetoThreshold);
    uint256 _proposalId = _proposeFromCouncil(_governor);

    // Voting is open, so the proposal's snapshot is before this change.
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _jumpPastTheProposalDeadline(_governor, _proposalId);

    _assertState(_governor, _proposalId, IGovernor.ProposalState.Defeated);
  }
}

contract ProposalDeadline is ZkProtocolUpgradeVetoGovernorTest {
  function testFuzz_ExtendsTheDeadlineWhenAgainstVotesReachTheExtensionShareOfTheVetoThreshold(
    uint256 _vetoThreshold,
    uint256 _againstVotes
  ) public {
    _vetoThreshold = _bound(_vetoThreshold, 2, MAX_VETO_THRESHOLD);
    _againstVotes = _bound(_againstVotes, _votingPeriodExtensionThreshold(_vetoThreshold), MAX_VETO_THRESHOLD);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_vetoThreshold);
    _mintAndSelfDelegateVotes(voter, _againstVotes);
    uint256 _proposalId = _proposeFromCouncil(_governor);
    uint256 _originalDeadline = _governor.proposalDeadline(_proposalId);

    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);

    assertEq(_governor.proposalDeadline(_proposalId), _originalDeadline + VOTING_PERIOD_EXTENSION);
  }

  function testFuzz_ExtendsAtTheShareOfTheVetoThresholdInForceAtTheProposalSnapshot(
    uint256 _initialVetoThreshold,
    uint256 _newVetoThreshold
  ) public {
    // AGAINST votes at the initial threshold's extension share are below the raised threshold's share, so the deadline
    // extends only if the snapshot's threshold applies.
    _initialVetoThreshold = _bound(_initialVetoThreshold, 2, MAX_VETO_THRESHOLD / 4);
    _newVetoThreshold = _bound(_newVetoThreshold, 4 * _initialVetoThreshold, MAX_VETO_THRESHOLD);
    uint256 _againstVotes = _votingPeriodExtensionThreshold(_initialVetoThreshold);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_initialVetoThreshold);
    _mintAndSelfDelegateVotes(voter, _againstVotes);
    uint256 _proposalId = _proposeFromCouncil(_governor);
    uint256 _originalDeadline = _governor.proposalDeadline(_proposalId);

    vm.warp(_governor.proposalSnapshot(_proposalId) + 1);
    _setVetoThresholdAsAdmin(_governor, _newVetoThreshold);
    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);

    assertEq(_governor.proposalDeadline(_proposalId), _originalDeadline + VOTING_PERIOD_EXTENSION);
  }

  function testFuzz_DoesNotExtendTheDeadlineWhenAgainstVotesAreBelowTheExtensionShareOfTheVetoThreshold(
    uint256 _vetoThreshold,
    uint256 _againstVotes
  ) public {
    // With a 50% extension share, a veto threshold of 2 or 3 extends at 1 vote, leaving no smaller non-zero vote.
    _vetoThreshold = _bound(_vetoThreshold, 4, MAX_VETO_THRESHOLD);
    _againstVotes = _bound(_againstVotes, 1, _votingPeriodExtensionThreshold(_vetoThreshold) - 1);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(_vetoThreshold);
    _mintAndSelfDelegateVotes(voter, _againstVotes);
    uint256 _proposalId = _proposeFromCouncil(_governor);
    uint256 _originalDeadline = _governor.proposalDeadline(_proposalId);

    _castAgainstVoteOnceVotingOpens(_governor, _proposalId);

    assertEq(_governor.proposalDeadline(_proposalId), _originalDeadline);
  }
}

contract UpdateVetoThresholdNumerator is ZkProtocolUpgradeVetoGovernorTest {
  function testFuzz_RevertIf_TheAdminSetsANonZeroNumerator(uint256 _newVetoThresholdNumerator) public {
    _newVetoThresholdNumerator = _bound(_newVetoThresholdNumerator, 1, type(uint256).max);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(MAX_VETO_THRESHOLD);

    vm.expectRevert(ZkProtocolUpgradeVetoGovernor.ZkProtocolUpgradeVetoGovernor__VetoThresholdFractionDisabled.selector);
    vm.prank(governorAdmin);
    _governor.updateVetoThresholdNumerator(_newVetoThresholdNumerator);
  }

  function test_LetsTheAdminSetAZeroNumeratorWithoutRecordingIt() public {
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(MAX_VETO_THRESHOLD);

    vm.recordLogs();
    vm.prank(governorAdmin);
    _governor.updateVetoThresholdNumerator(0);

    assertEq(_countLogsEmittedBy(address(_governor)), 0);
    assertEq(_governor.vetoThresholdNumerator(), 0);
    assertEq(_governor.vetoThreshold(block.timestamp), MAX_VETO_THRESHOLD);
  }

  function testFuzz_RevertIf_TheCallerIsNotTheGovernorAdmin(address _caller) public {
    _assumeNotASystemAddress(_caller);
    vm.assume(_caller != governorAdmin);
    ZkProtocolUpgradeVetoGovernor _governor = _deployGovernorWithVetoThreshold(MAX_VETO_THRESHOLD);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
    vm.prank(_caller);
    _governor.updateVetoThresholdNumerator(0);
  }
}
