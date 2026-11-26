// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {GovernorSettableFixedQuorum} from "src/extensions/GovernorSettableFixedQuorum.sol";
import {ZkProtocolGovernorHarness} from "test/harnesses/ZkProtocolGovernorHarness.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";
import {TimelockControllerFake} from "test/fakes/TimelockControllerFake.sol";

contract GovernorSettableFixedQuorumTest is Test {
  uint48 constant INITIAL_VOTING_DELAY = 1 days;
  uint32 constant INITIAL_VOTING_PERIOD = 7 days;
  uint256 constant INITIAL_PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant INITIAL_QUORUM = 1_000_000e18;
  uint64 constant INITIAL_VOTE_EXTENSION = 1 days;

  TimelockControllerFake timelock;
  ERC20VotesFake token;
  ZkProtocolGovernorHarness governor;

  function setUp() public {
    address _initialOwner = makeAddr("Initial Owner");
    timelock = new TimelockControllerFake(_initialOwner);
    token = new ERC20VotesFake();
    governor = new ZkProtocolGovernorHarness(
      "Example Gov",
      token,
      timelock,
      INITIAL_VOTING_DELAY,
      INITIAL_VOTING_PERIOD,
      INITIAL_PROPOSAL_THRESHOLD,
      INITIAL_QUORUM,
      INITIAL_VOTE_EXTENSION
    );

    vm.prank(_initialOwner);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(_initialOwner);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));
  }
}

contract Quorum is GovernorSettableFixedQuorumTest {
  function testFuzz_SuccessfullyGetLatestQuorumCheckpoint(uint208 _quorum) public {
    governor.exposed_setQuorum(_quorum);
    uint256 _quorumValue = governor.quorum(block.timestamp);
    assertEq(_quorumValue, _quorum);
  }
}

contract SetQuorum is GovernorSettableFixedQuorumTest, ProposalTest {
  function testFuzz_CorrectlySetQuorumCheckpoint(uint224 _quorum) public {
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
    _builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", _quorum));
    _queueAndVoteAndExecuteProposal(_builder.targets(), _builder.values(), _builder.calldatas(), "Description", 1);
    assertEq(governor.quorum(block.timestamp), _quorum);
  }

  function testFuzz_CorrectlyEmitQuorumUpdatedEvent(uint224 _quorum) public {
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
    _builder.push(address(governor), 0, abi.encodeWithSignature("setQuorum(uint224)", _quorum));
    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    string memory _description = "Description";

    uint256 _proposalId = _propose(_targets, _values, _calldatas, _description);
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, 1);
    _jumpPastVoteComplete(_proposalId);

    governor.queue(_targets, _values, _calldatas, keccak256(bytes(_description)));

    _jumpPastProposalEta(_proposalId);

    vm.expectEmit();
    emit GovernorSettableFixedQuorum.QuorumUpdated(INITIAL_QUORUM, _quorum);
    governor.execute(_targets, _values, _calldatas, keccak256(bytes(_description)));
  }

  function testFuzz_RevertIf_CallerIsNotAuthorized(uint208 _quorum, address _caller) public {
    vm.assume(_caller != address(timelock));
    vm.prank(_caller);
    vm.expectRevert(bytes("Governor: onlyGovernance"));
    governor.setQuorum(_quorum);
  }
}
