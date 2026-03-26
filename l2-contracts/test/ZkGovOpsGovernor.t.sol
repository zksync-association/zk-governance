// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Test} from "forge-std/Test.sol";

import {ZkGovOpsGovernor} from "src/ZkGovOpsGovernor.sol";
import {GovernorGuardianVeto} from "src/extensions/GovernorGuardianVeto.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {TimelockControllerFake} from "test/fakes/TimelockControllerFake.sol";

contract ZkGovOpsGovernorTest is Test {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;
  string constant DESCRIPTION = "Description";
  address initialOwner;
  address vetoGuardian;

  TimelockControllerFake timelock;
  ERC20VotesFake token;
  ZkGovOpsGovernor governor;

  function setUp() public {
    initialOwner = makeAddr("Initial Owner");
    vetoGuardian = makeAddr("Veto Guardian");
    timelock = new TimelockControllerFake(initialOwner);
    token = new ERC20VotesFake();
    ZkGovOpsGovernor.ConstructorParams memory _params = ZkGovOpsGovernor.ConstructorParams({
      name: "Example Gov",
      token: token,
      timelock: timelock,
      initialVotingDelay: INITIAL_VOTING_DELAY,
      initialVotingPeriod: INITIAL_VOTING_PERIOD,
      initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
      initialQuorum: INITIAL_QUORUM,
      initialVoteExtension: INITIAL_VOTE_EXTENSION,
      vetoGuardian: vetoGuardian
    });
    governor = new ZkGovOpsGovernor(_params);

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
  }
}

contract Cancel is ZkGovOpsGovernorTest, ProposalTest {
  function _buildProposal() internal returns (ProposalBuilder, address) {
    address _delegate = makeAddr("delegate");
    token.mint(_delegate, governor.proposalThreshold());
    token.mint(_delegate, governor.quorum(block.timestamp));

    vm.prank(_delegate);
    token.delegate(_delegate);

    vm.warp(block.timestamp + 1);
    address[] memory _delegates = new address[](1);
    _delegates[0] = _delegate;
    _setGovernor(governor);
    _setDelegates(_delegates);
    ProposalBuilder _builder = new ProposalBuilder();
    _builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", 1));
    return (_builder, _delegate);
  }

  function test_CorrectlyCancelPendingProposal() public {
    (ProposalBuilder _builder,) = _buildProposal();
    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Pending));

    vm.startPrank(vetoGuardian);
    governor.cancel(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();

    IGovernor.ProposalState _canceledState = governor.state(_proposalId);
    assertEq(uint8(_canceledState), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_CorrectlyCancelActiveProposal() public {
    (ProposalBuilder _builder,) = _buildProposal();

    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Active));

    vm.startPrank(vetoGuardian);
    governor.cancel(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();

    IGovernor.ProposalState _canceledState = governor.state(_proposalId);
    assertEq(uint8(_canceledState), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_RevertIf_DefeatedProposalIsCanceled() public {
    (ProposalBuilder _builder,) = _buildProposal();

    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.Against)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Defeated));

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();

    vm.startPrank(vetoGuardian);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_UncancelableProposalState.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_SucceededProposalIsCanceled() public {
    (ProposalBuilder _builder,) = _buildProposal();

    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Succeeded));

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();

    vm.startPrank(vetoGuardian);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_UncancelableProposalState.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_QueuedProposalIsCanceled() public {
    (ProposalBuilder _builder,) = _buildProposal();

    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);
    governor.queue(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(DESCRIPTION)));

    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Queued));

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();

    vm.startPrank(vetoGuardian);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_UncancelableProposalState.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_ExecutedProposalIsCanceled() public {
    (ProposalBuilder _builder,) = _buildProposal();

    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();

    governor.queue(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    _jumpPastProposalEta(_proposalId);
    governor.execute(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));

    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Executed));

    vm.startPrank(vetoGuardian);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_UncancelableProposalState.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CancelledByNonGuardian(address _caller) public {
    vm.assume(_caller != vetoGuardian);
    (ProposalBuilder _builder,) = _buildProposal();
    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), DESCRIPTION);
    IGovernor.ProposalState _proposalState = governor.state(_proposalId);
    assertEq(uint8(_proposalState), uint8(IGovernor.ProposalState.Pending));

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();

    vm.startPrank(_caller);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_Unauthorized.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }
}
