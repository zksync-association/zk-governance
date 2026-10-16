// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorTimelock} from "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ZkTokenGovernor} from "src/ZkTokenGovernor.sol";
import {GovernorGuardianVeto} from "src/extensions/GovernorGuardianVeto.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {ERC20VotesFake} from "test/fakes/ERC20VotesFake.sol";

/// @dev The address an L1 contract appears as on L2 when it sends an L1 -> L2 transaction.
function applyL1ToL2Alias(address _l1Address) pure returns (address) {
  unchecked {
    return address(uint160(_l1Address) + uint160(0x1111000000000000000000000000000000001111));
  }
}

/// @dev Exercises the guardians removal on the ZkTokenGovernor: a redeployed governor with the ZK
/// Foundation Safe in the `VETO_GUARDIAN` seat takes over the timelock (and with it the treasury and
/// the minter admin roles) through the role migration proposal that `RedeployZkTokenGovernor.ts`
/// prints, passed on the current governor (TPP).
abstract contract GuardiansRemovalGovernorMigrationTest is ProposalTest {
  uint48 constant VOTING_DELAY = 1 days;
  uint32 constant VOTING_PERIOD = 7 days;
  uint256 constant PROPOSAL_THRESHOLD = 500_000e18;
  uint224 constant QUORUM = 1_000_000e18;
  uint64 constant VOTE_EXTENSION = 1 days;
  uint256 constant TIMELOCK_DELAY = 3 days;

  bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
  bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  // Today the veto seat is held by the L1 Guardians multisig through its L2 alias.
  address guardiansAlias = applyL1ToL2Alias(makeAddr("L1 Guardians"));
  address zkFoundationSafe = makeAddr("ZK Foundation Safe (Era)");
  address delegate = makeAddr("delegate");

  ERC20VotesFake token;
  TimelockController timelock;
  IGovernorTimelock oldGovernor;
  IGovernorTimelock newGovernor;

  function _deployGovernor(address _vetoGuardian) internal virtual returns (IGovernorTimelock);

  function setUp() public {
    token = new ERC20VotesFake();
    token.mint(delegate, PROPOSAL_THRESHOLD + QUORUM);
    vm.prank(delegate);
    token.delegate(delegate);
    vm.warp(block.timestamp + 1);
    _setDelegates(delegate);

    // Same shape as on Era: the timelock administers itself and the governor holds every role.
    address _deployer = makeAddr("deployer");
    timelock = new TimelockController(TIMELOCK_DELAY, new address[](0), new address[](0), _deployer);
    oldGovernor = _deployGovernor(guardiansAlias);
    vm.startPrank(_deployer);
    timelock.grantRole(PROPOSER_ROLE, address(oldGovernor));
    timelock.grantRole(CANCELLER_ROLE, address(oldGovernor));
    timelock.grantRole(EXECUTOR_ROLE, address(oldGovernor));
    timelock.renounceRole(TIMELOCK_ADMIN_ROLE, _deployer);
    vm.stopPrank();

    newGovernor = _deployGovernor(zkFoundationSafe);
  }

  /// @dev The role migration printed by the redeploy scripts: grants first, revokes second.
  function _migrationProposal() internal returns (ProposalBuilder _builder) {
    _builder = new ProposalBuilder();
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.grantRole, (PROPOSER_ROLE, address(newGovernor))));
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.grantRole, (CANCELLER_ROLE, address(newGovernor))));
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.grantRole, (EXECUTOR_ROLE, address(newGovernor))));
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.revokeRole, (PROPOSER_ROLE, address(oldGovernor))));
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.revokeRole, (CANCELLER_ROLE, address(oldGovernor))));
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.revokeRole, (EXECUTOR_ROLE, address(oldGovernor))));
  }

  function _migrate() internal {
    ProposalBuilder _builder = _migrationProposal();
    _setGovernor(oldGovernor);
    _queueAndVoteAndExecuteProposal(
      _builder.targets(), _builder.values(), _builder.calldatas(), "Migrate timelock roles", uint8(VoteType.For)
    );
  }

  function _updateDelayProposal(uint256 _newDelay) internal returns (ProposalBuilder _builder) {
    _builder = new ProposalBuilder();
    _builder.push(address(timelock), 0, abi.encodeCall(timelock.updateDelay, (_newDelay)));
  }

  function test_MigrationMovesTimelockRoles() public {
    _migrate();

    assertTrue(timelock.hasRole(PROPOSER_ROLE, address(newGovernor)));
    assertTrue(timelock.hasRole(CANCELLER_ROLE, address(newGovernor)));
    assertTrue(timelock.hasRole(EXECUTOR_ROLE, address(newGovernor)));
    assertFalse(timelock.hasRole(PROPOSER_ROLE, address(oldGovernor)));
    assertFalse(timelock.hasRole(CANCELLER_ROLE, address(oldGovernor)));
    assertFalse(timelock.hasRole(EXECUTOR_ROLE, address(oldGovernor)));
  }

  function test_NewGovernorExecutesThroughTimelock() public {
    _migrate();

    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(newGovernor);
    _queueAndVoteAndExecuteProposal(
      _builder.targets(), _builder.values(), _builder.calldatas(), "Update delay", uint8(VoteType.For)
    );

    assertEq(timelock.getMinDelay(), 1 days);
  }

  function test_RevertWhen_OldGovernorQueuesAfterMigration() public {
    _migrate();

    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(oldGovernor);
    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), "Update delay");
    _passProposal(_proposalId);
    assertEq(uint8(oldGovernor.state(_proposalId)), uint8(IGovernor.ProposalState.Succeeded));

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    vm.expectRevert();
    oldGovernor.queue(_targets, _values, _calldatas, keccak256(bytes("Update delay")));
  }

  function test_FoundationCanVetoOnNewGovernor() public {
    _migrate();

    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(newGovernor);
    uint256 _proposalId = _propose(_builder.targets(), _builder.values(), _builder.calldatas(), "Update delay");

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    vm.prank(zkFoundationSafe);
    newGovernor.cancel(_targets, _values, _calldatas, keccak256(bytes("Update delay")));

    assertEq(uint8(newGovernor.state(_proposalId)), uint8(IGovernor.ProposalState.Canceled));
  }

  function test_RevertWhen_GuardiansVetoOnNewGovernor() public {
    _migrate();

    ProposalBuilder _builder = _updateDelayProposal(1 days);
    _setGovernor(newGovernor);
    _propose(_builder.targets(), _builder.values(), _builder.calldatas(), "Update delay");

    address[] memory _targets = _builder.targets();
    uint256[] memory _values = _builder.values();
    bytes[] memory _calldatas = _builder.calldatas();
    vm.prank(guardiansAlias);
    vm.expectRevert(GovernorGuardianVeto.GovernorGuardianVeto_Unauthorized.selector);
    newGovernor.cancel(_targets, _values, _calldatas, keccak256(bytes("Update delay")));
  }
}

contract ZkTokenGovernorGuardiansRemovalMigration is GuardiansRemovalGovernorMigrationTest {
  // The propose seat is not a Guardians seat and stays with the ZK Foundation (L1 Safe alias).
  address proposeGuardian = applyL1ToL2Alias(makeAddr("L1 ZK Foundation Safe"));

  function _deployGovernor(address _vetoGuardian) internal override returns (IGovernorTimelock) {
    return IGovernorTimelock(
      address(
        new ZkTokenGovernor(
          ZkTokenGovernor.ConstructorParams({
            name: "ZkTokenGovernor",
            token: token,
            timelock: timelock,
            initialVotingDelay: VOTING_DELAY,
            initialVotingPeriod: VOTING_PERIOD,
            initialProposalThreshold: PROPOSAL_THRESHOLD,
            initialQuorum: QUORUM,
            initialVoteExtension: VOTE_EXTENSION,
            vetoGuardian: _vetoGuardian,
            proposeGuardian: proposeGuardian,
            isProposeGuarded: false
          })
        )
      )
    );
  }
}
