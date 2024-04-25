// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Test, console2} from "forge-std/Test.sol";

import {ZkSocialGovernor} from "src/ZkSocialGovernor.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {TimelockControllerFake} from "test/fakes/TimelockControllerFake.sol";

contract ZkSocialGovernorTest is Test {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;
  string constant DESCRIPTION = "Description";
  address initialOwner;
  address initialGuardian;

  TimelockControllerFake timelock;
  ERC20VotesFake token;
  ZkSocialGovernor governor;

  function setUp() public {
    initialOwner = makeAddr("Initial Owner");
    initialGuardian = makeAddr("Guardian");
    timelock = new TimelockControllerFake(initialOwner);
    token = new ERC20VotesFake();
    governor = new ZkSocialGovernor(
      "Example Gov",
      token,
      timelock,
      INITIAL_VOTING_DELAY,
      INITIAL_VOTING_PERIOD,
      INITIAL_PROPOSAL_THRESHOLD,
      INITIAL_QUORUM,
      INITIAL_VOTE_EXTENSION,
      initialGuardian
    );

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(initialOwner);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
  }
}

contract Cancel is ZkSocialGovernorTest, ProposalTest {
  function _buildProposal() internal returns (ProposalBuilder, address) {
    address delegate = makeAddr("delegate");
    token.mint(delegate, governor.proposalThreshold());
    token.mint(delegate, governor.quorum(block.timestamp));

    vm.prank(delegate);
    token.delegate(delegate);

    vm.warp(block.timestamp + 1);
    address[] memory delegates = new address[](1);
    delegates[0] = delegate;
    _setGovernor(governor);
    _setDelegates(delegates);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", 1));
    return (builder, delegate);
  }

  function test_CorrectlyCancelPendingProposal() public {
    (ProposalBuilder builder,) = _buildProposal();
    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Pending));

    vm.startPrank(initialGuardian);
    governor.cancel(builder.targets(), builder.values(), builder.calldatas(), keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();

    IGovernor.ProposalState canceledState = governor.state(_proposalId);
    assertEq(uint8(canceledState), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_CorrectlyCancelActiveProposal() public {
    (ProposalBuilder builder,) = _buildProposal();

    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Active));

    vm.startPrank(initialGuardian);
    governor.cancel(builder.targets(), builder.values(), builder.calldatas(), keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();

    IGovernor.ProposalState canceledState = governor.state(_proposalId);
    assertEq(uint8(canceledState), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_RevertIf_DefeatedProposalIsCanceled() public {
    (ProposalBuilder builder,) = _buildProposal();

    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.Against)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Defeated));

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    vm.startPrank(initialGuardian);
    vm.expectRevert(ZkSocialGovernor.UncancellableProposalState.selector);
    governor.cancel(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_SucceededProposalIsCanceled() public {
    (ProposalBuilder builder,) = _buildProposal();

    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Succeeded));

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    vm.startPrank(initialGuardian);
    vm.expectRevert(ZkSocialGovernor.UncancellableProposalState.selector);
    governor.cancel(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_QueuedProposalIsCanceled() public {
    (ProposalBuilder builder,) = _buildProposal();

    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);
    governor.queue(builder.targets(), builder.values(), builder.calldatas(), keccak256(bytes(DESCRIPTION)));

    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Queued));

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    vm.startPrank(initialGuardian);
    vm.expectRevert(ZkSocialGovernor.UncancellableProposalState.selector);
    governor.cancel(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function test_RevertIf_ExecutedProposalIsCanceled() public {
    (ProposalBuilder builder,) = _buildProposal();

    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    _jumpToActiveProposal(_proposalId);
    _delegatesVote(_proposalId, uint8(VoteType.For)); // VoteType
    _jumpPastVoteComplete(_proposalId);

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    governor.queue(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    _jumpPastProposalEta(_proposalId);
    governor.execute(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));

    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Executed));

    vm.startPrank(initialGuardian);
    vm.expectRevert(ZkSocialGovernor.UncancellableProposalState.selector);
    governor.cancel(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }

  function testFuzz_RevertIf_CancelledByNonGuardian(address _caller) public {
    vm.assume(_caller != initialGuardian);
    (ProposalBuilder builder,) = _buildProposal();
    uint256 _proposalId = _propose(builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION);
    IGovernor.ProposalState proposalState = governor.state(_proposalId);
    assertEq(uint8(proposalState), uint8(IGovernor.ProposalState.Pending));

    address[] memory targets = builder.targets();
    uint256[] memory values = builder.values();
    bytes[] memory calldatas = builder.calldatas();

    vm.startPrank(_caller);
    vm.expectRevert(ZkSocialGovernor.Unauthorized.selector);
    governor.cancel(targets, values, calldatas, keccak256(bytes(DESCRIPTION)));
    vm.stopPrank();
  }
}

contract SetGuardian is ZkSocialGovernorTest, ProposalTest {
  function testFuzz_CorrectlySetGuardian(address _guardian) public {
    address delegate = makeAddr("delegate");
    token.mint(delegate, governor.proposalThreshold());
    token.mint(delegate, governor.quorum(block.timestamp));

    vm.prank(delegate);
    token.delegate(delegate);

    vm.warp(block.timestamp + 1);
    address[] memory delegates = new address[](1);
    delegates[0] = delegate;
    _setGovernor(governor);
    _setDelegates(delegates);
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(address(governor), 0, abi.encodeWithSignature("setGuardian(address)", _guardian));
    _queueAndVoteAndExecuteProposal(
      builder.targets(), builder.values(), builder.calldatas(), DESCRIPTION, uint8(VoteType.For)
    );
    assertEq(governor.guardian(), _guardian);
  }

  function testFuzz_RevertIf_CallerIsNotAuthorized(address _guardian, address _caller) public {
    vm.assume(_caller != address(timelock));
    vm.prank(_caller);
    vm.expectRevert(bytes("Governor: onlyGovernance"));
    governor.setGuardian(_guardian);
  }
}
