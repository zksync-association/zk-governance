// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorTimelock} from "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ZkGovOpsGovernor} from "src/ZkGovOpsGovernor.sol";
import {GovernorGuardianVeto} from "src/extensions/GovernorGuardianVeto.sol";
import {DeployZkGovOpsGovernorWithTimelock} from "script/DeployZkGovOpsGovernorWithTimelock.s.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";

contract DeployZkGovOpsGovernorWithTimelockTest is ProposalTest {
  uint48 constant VOTING_DELAY = 3 days;
  uint32 constant VOTING_PERIOD = 7 days;
  uint256 constant PROPOSAL_THRESHOLD = 21_000_000e18;
  uint224 constant QUORUM = 630_000_000e18;
  uint64 constant VOTE_EXTENSION = 2 days;
  uint256 constant TIMELOCK_DELAY = 3 days;

  bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
  bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  // The L2 alias of the L1 Guardians, the veto seat of the current governor.
  address guardiansAlias = makeAddr("L1 Guardians alias");
  address zkFoundationSafe = makeAddr("ZK Foundation Safe (Era)");
  address delegate = makeAddr("delegate");

  ERC20VotesFake token;
  TimelockController currentTimelock;
  ZkGovOpsGovernor currentGovernor;
  DeployZkGovOpsGovernorWithTimelock script;
  TimelockController timelock;
  ZkGovOpsGovernor governor;

  function setUp() public {
    token = new ERC20VotesFake();
    token.mint(delegate, PROPOSAL_THRESHOLD + QUORUM);
    vm.prank(delegate);
    token.delegate(delegate);
    vm.warp(block.timestamp + 1);
    _setDelegates(delegate);

    // The current GovOps governor and its timelock, configured like on Era.
    address _deployer = makeAddr("deployer");
    currentTimelock = new TimelockController(TIMELOCK_DELAY, new address[](0), new address[](0), _deployer);
    currentGovernor = new ZkGovOpsGovernor(
      ZkGovOpsGovernor.ConstructorParams({
        name: "ZkGovOpsGovernor",
        token: token,
        timelock: currentTimelock,
        initialVotingDelay: VOTING_DELAY,
        initialVotingPeriod: VOTING_PERIOD,
        initialProposalThreshold: PROPOSAL_THRESHOLD,
        initialQuorum: QUORUM,
        initialVoteExtension: VOTE_EXTENSION,
        vetoGuardian: guardiansAlias
      })
    );
    vm.startPrank(_deployer);
    currentTimelock.grantRole(PROPOSER_ROLE, address(currentGovernor));
    currentTimelock.grantRole(CANCELLER_ROLE, address(currentGovernor));
    currentTimelock.grantRole(EXECUTOR_ROLE, address(currentGovernor));
    currentTimelock.renounceRole(TIMELOCK_ADMIN_ROLE, _deployer);
    vm.stopPrank();

    script = new DeployZkGovOpsGovernorWithTimelock();
    (timelock, governor) = script.deploy(currentGovernor, zkFoundationSafe, address(script));
  }

  function _updateDelayProposal(uint256 _newDelay) internal returns (ProposalBuilder _builder) {
    _builder = new ProposalBuilder();
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.updateDelay, (_newDelay)));
  }

  function test_NewTimelockIsSelfAdministeredAndDrivenByTheNewGovernor() public {
    assertEq(timelock.getMinDelay(), TIMELOCK_DELAY);
    assertTrue(timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(timelock)));
    assertFalse(timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(script)));
    assertTrue(timelock.hasRole(PROPOSER_ROLE, address(governor)));
    assertTrue(timelock.hasRole(CANCELLER_ROLE, address(governor)));
    assertTrue(timelock.hasRole(EXECUTOR_ROLE, address(governor)));
    assertFalse(timelock.hasRole(EXECUTOR_ROLE, address(0)));
  }

  function test_NewGovernorCopiesTheCurrentSettings() public {
    assertEq(governor.name(), currentGovernor.name());
    assertEq(address(governor.token()), address(currentGovernor.token()));
    assertEq(governor.timelock(), address(timelock));
    assertEq(governor.votingDelay(), currentGovernor.votingDelay());
    assertEq(governor.votingPeriod(), currentGovernor.votingPeriod());
    assertEq(governor.proposalThreshold(), currentGovernor.proposalThreshold());
    assertEq(governor.quorum(governor.clock()), currentGovernor.quorum(currentGovernor.clock()));
    assertEq(governor.lateQuorumVoteExtension(), currentGovernor.lateQuorumVoteExtension());
    assertEq(governor.VETO_GUARDIAN(), zkFoundationSafe);
  }

  function test_CurrentPairIsUntouched() public {
    assertTrue(currentTimelock.hasRole(PROPOSER_ROLE, address(currentGovernor)));
    assertFalse(currentTimelock.hasRole(PROPOSER_ROLE, address(governor)));
  }

  function test_NewGovernorExecutesThroughTheNewTimelock() public {
    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(IGovernorTimelock(address(governor)));
    _queueAndVoteAndExecuteProposal(
      _builder.targets(), _builder.values(), _builder.calldatas(), "Update delay", uint8(VoteType.For)
    );

    assertEq(timelock.getMinDelay(), 1 days);
  }

  function test_FoundationCanVeto() public {
    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(IGovernorTimelock(address(governor)));
    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), "Update delay");

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    vm.prank(zkFoundationSafe);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes("Update delay")));

    assertEq(uint8(governor.state(_proposalId)), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_RevertWhen_GuardiansVeto() public {
    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(IGovernorTimelock(address(governor)));
    _propose(_builder.targets(), _builder.values(), _builder.calldatas(), "Update delay");

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    vm.prank(guardiansAlias);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_Unauthorized.selector);
    governor.cancel(_targets, _values, _calldatas, keccak256(bytes("Update delay")));
  }
}
