// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, Vm} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {
  ProposeProtocolTimelockRoleMigrationEraMainnet
} from "script/ProposeProtocolTimelockRoleMigrationEraMainnet.s.sol";
import {
  ProposeProtocolTimelockRoleMigrationEraMainnetHarness
} from "test/harnesses/ProposeProtocolTimelockRoleMigrationEraMainnetHarness.sol";
import {IZkCheatcodes} from "test/interfaces/IZkCheatcodes.sol";

/// @notice Runs the Era mainnet role migration script on a fork of Era mainnet, against the live `ZkProtocolGovernor`,
/// Protocol Timelock and ZK token.
/// @dev Run under `--zksync`, since the forked contracts are EraVM contracts. The script is deployed and run in the
/// EVM, as `forge script --zksync` runs it, because EraVM has no cheatcodes; its calls to the forked contracts still
/// run in EraVM. It broadcasts from the default sender, which the tests make a ZK delegate.
contract ProposeProtocolTimelockRoleMigrationTest is Test {
  // A fork block from before the migration, while `ZkProtocolGovernor` holds the Protocol Timelock roles.
  uint256 constant FORK_BLOCK = 72_650_000;

  address constant ZK_TOKEN = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  IGovernor constant PROTOCOL_GOVERNOR = IGovernor(0x76705327e682F2d96943280D99464Ab61219e34f);
  TimelockController constant PROTOCOL_TIMELOCK =
    TimelockController(payable(0x085b8B6407f150D62adB1EF926F7f304600ec714));

  bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
  // The Protocol Timelock is OpenZeppelin v4, whose admin role is TIMELOCK_ADMIN_ROLE.
  bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  // OpenZeppelin v4's `ProposalCreated`, which `ZkProtocolGovernor` emits.
  bytes32 constant PROPOSAL_CREATED =
    keccak256("ProposalCreated(uint256,address,address[],uint256[],string[],bytes[],uint256,uint256,string)");

  address vetoGovernor = makeAddr("Veto Governor");

  // A `ZkProtocolGovernor` proposal, as `ProposalCreated` reports it.
  struct CreatedProposal {
    uint256 proposalId;
    address proposer;
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
  }

  function setUp() public virtual {
    vm.createSelectFork(vm.envOr("ZKSYNC_RPC_URL", string("https://mainnet.era.zksync.io")), FORK_BLOCK);
    // The default sender pays for the EraVM calls the script broadcasts.
    vm.deal(DEFAULT_SENDER, 1 ether);
  }

  // Deploys the script in the EVM rather than EraVM, which matches production: `forge script --zksync` never deploys a
  // script, it runs the script locally in the EVM, where cheatcodes exist, and sends only its broadcast transactions to
  // Era. Under `--zksync` a plain `new` would deploy the script to EraVM, which has no cheatcodes, so its first `vm.*`
  // call would revert. Calls to the script then run in the EVM too, while its calls to the forked governor, timelock
  // and token still run in EraVM against their live bytecode. This would be wrong for a script that deploys contracts,
  // since anything it creates would also land in the EVM, but this script deploys nothing.
  function _deployScript(address _vetoGovernor) internal returns (ProposeProtocolTimelockRoleMigrationEraMainnet) {
    IZkCheatcodes(address(vm)).zkVmSkip();
    ProposeProtocolTimelockRoleMigrationEraMainnet _script =
      new ProposeProtocolTimelockRoleMigrationEraMainnetHarness(_vetoGovernor);
    _script.disableLogging();
    return _script;
  }

  // Runs the script and returns the proposal it made.
  function _runAndRecordProposal(address _vetoGovernor) internal returns (CreatedProposal memory) {
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(_vetoGovernor);
    vm.recordLogs();
    _script.run();
    return _createdProposal(vm.getRecordedLogs());
  }

  // Finds the one proposal `ZkProtocolGovernor` created in `_logs`.
  function _createdProposal(Vm.Log[] memory _logs) internal pure returns (CreatedProposal memory _proposal) {
    uint256 _found;
    for (uint256 _i = 0; _i < _logs.length; _i += 1) {
      if (_logs[_i].emitter != address(PROTOCOL_GOVERNOR) || _logs[_i].topics[0] != PROPOSAL_CREATED) {
        continue;
      }
      _found += 1;
      (
        _proposal.proposalId,
        _proposal.proposer,
        _proposal.targets,
        _proposal.values,,
        _proposal.calldatas,,,
        _proposal.description
      ) =
        abi.decode(
          _logs[_i].data, (uint256, address, address[], uint256[], string[], bytes[], uint256, uint256, string)
        );
    }
    assertEq(_found, 1, "expected exactly one ZkProtocolGovernor proposal");
  }

  // Gives `_delegate` `_votes` ZK votes, counted from the next timestamp on.
  function _dealVotes(address _delegate, uint256 _votes) internal {
    deal(ZK_TOKEN, _delegate, _votes);
    vm.prank(_delegate);
    IVotes(ZK_TOKEN).delegate(_delegate);
    vm.warp(block.timestamp + 1);
  }

  // Makes the default sender, which the script broadcasts from, a delegate at `ZkProtocolGovernor`'s threshold.
  function _dealProposerVotes() internal {
    _dealVotes(DEFAULT_SENDER, PROTOCOL_GOVERNOR.proposalThreshold());
  }

  // Changes a Protocol Timelock role as the timelock, which administers itself.
  function _grantTimelockRole(bytes32 _role, address _account) internal {
    vm.prank(address(PROTOCOL_TIMELOCK));
    PROTOCOL_TIMELOCK.grantRole(_role, _account);
  }

  // Excludes the accounts the Veto Governor cannot be: the zero address, which the timelock treats as every account,
  // `ZkProtocolGovernor`, which gives up the roles, the Protocol Timelock, which administers itself, and any account
  // already holding one of the roles.
  function _assumeValidVetoGovernor(address _vetoGovernor) internal view {
    vm.assume(_vetoGovernor != address(0));
    vm.assume(_vetoGovernor != address(PROTOCOL_GOVERNOR));
    vm.assume(_vetoGovernor != address(PROTOCOL_TIMELOCK));
    bytes32[3] memory _roles = _migratedRoles();
    for (uint256 _i = 0; _i < 3; _i += 1) {
      vm.assume(!PROTOCOL_TIMELOCK.hasRole(_roles[_i], _vetoGovernor));
    }
  }

  function _migratedRoles() internal pure returns (bytes32[3] memory) {
    return [PROPOSER_ROLE, EXECUTOR_ROLE, CANCELLER_ROLE];
  }

  function _boundToMigratedRole(uint256 _roleIndex) internal pure returns (bytes32) {
    return _migratedRoles()[_bound(_roleIndex, 0, 2)];
  }

  // The name the script reports for a proposal state.
  function _proposalStateName(IGovernor.ProposalState _state) internal pure returns (string memory) {
    string[8] memory _stateNames =
      ["Pending", "Active", "Canceled", "Defeated", "Succeeded", "Queued", "Expired", "Executed"];
    return _stateNames[uint8(_state)];
  }
}

// Every run forks Era mainnet and fetches state over RPC, so these tests fuzz fewer runs than the default.
/// forge-config: default.fuzz.runs = 16
/// forge-config: ci.fuzz.runs = 16
/// forge-config: lite.fuzz.runs = 4
contract Run is ProposeProtocolTimelockRoleMigrationTest {
  function testFuzz_ProposesTheMigrationFromTheBroadcaster(address _vetoGovernor) public {
    _assumeValidVetoGovernor(_vetoGovernor);
    _dealProposerVotes();

    CreatedProposal memory _proposal = _runAndRecordProposal(_vetoGovernor);

    assertEq(_proposal.proposer, DEFAULT_SENDER);
    assertEq(uint8(PROTOCOL_GOVERNOR.state(_proposal.proposalId)), uint8(IGovernor.ProposalState.Pending));
  }

  function testFuzz_GrantsEveryRoleToTheVetoGovernorBeforeRevokingAnyFromZkProtocolGovernor(address _vetoGovernor)
    public
  {
    _assumeValidVetoGovernor(_vetoGovernor);
    _dealProposerVotes();

    CreatedProposal memory _proposal = _runAndRecordProposal(_vetoGovernor);

    address _timelock = address(PROTOCOL_TIMELOCK);
    address _governor = address(PROTOCOL_GOVERNOR);
    assertEq(_proposal.targets.length, 6);
    assertEq(_proposal.values, new uint256[](6));
    assertEq(_proposal.targets[0], _timelock);
    assertEq(_proposal.calldatas[0], abi.encodeCall(IAccessControl.grantRole, (PROPOSER_ROLE, _vetoGovernor)));
    assertEq(_proposal.targets[1], _timelock);
    assertEq(_proposal.calldatas[1], abi.encodeCall(IAccessControl.grantRole, (EXECUTOR_ROLE, _vetoGovernor)));
    assertEq(_proposal.targets[2], _timelock);
    assertEq(_proposal.calldatas[2], abi.encodeCall(IAccessControl.grantRole, (CANCELLER_ROLE, _vetoGovernor)));
    assertEq(_proposal.targets[3], _timelock);
    assertEq(_proposal.calldatas[3], abi.encodeCall(IAccessControl.revokeRole, (PROPOSER_ROLE, _governor)));
    assertEq(_proposal.targets[4], _timelock);
    assertEq(_proposal.calldatas[4], abi.encodeCall(IAccessControl.revokeRole, (EXECUTOR_ROLE, _governor)));
    assertEq(_proposal.targets[5], _timelock);
    assertEq(_proposal.calldatas[5], abi.encodeCall(IAccessControl.revokeRole, (CANCELLER_ROLE, _governor)));
  }

  function testFuzz_MigratesTheProtocolTimelockRolesToTheVetoGovernor(address _vetoGovernor) public {
    _assumeValidVetoGovernor(_vetoGovernor);
    _dealProposerVotes();

    CreatedProposal memory _proposal = _runAndRecordProposal(_vetoGovernor);

    assertTrue(
      PROTOCOL_TIMELOCK.isOperationDone(
        PROTOCOL_TIMELOCK.hashOperationBatch(
          _proposal.targets, _proposal.values, _proposal.calldatas, bytes32(0), keccak256(bytes(_proposal.description))
        )
      )
    );
    bytes32[3] memory _roles = _migratedRoles();
    for (uint256 _i = 0; _i < 3; _i += 1) {
      assertTrue(PROTOCOL_TIMELOCK.hasRole(_roles[_i], _vetoGovernor));
      assertFalse(PROTOCOL_TIMELOCK.hasRole(_roles[_i], address(PROTOCOL_GOVERNOR)));
    }
    assertTrue(PROTOCOL_TIMELOCK.hasRole(TIMELOCK_ADMIN_ROLE, address(PROTOCOL_TIMELOCK)));
    assertEq(PROTOCOL_TIMELOCK.getMinDelay(), 0);

    // The Veto Governor can now schedule and execute through the timelock, and `ZkProtocolGovernor` can no longer
    // schedule.
    address[] memory _targets = new address[](1);
    _targets[0] = address(PROTOCOL_TIMELOCK);
    uint256[] memory _values = new uint256[](1);
    bytes[] memory _calldatas = new bytes[](1);
    _calldatas[0] = abi.encodeCall(IAccessControl.grantRole, (PROPOSER_ROLE, _vetoGovernor));
    vm.prank(_vetoGovernor);
    PROTOCOL_TIMELOCK.scheduleBatch(_targets, _values, _calldatas, bytes32(0), bytes32(0), 0);
    vm.prank(_vetoGovernor);
    PROTOCOL_TIMELOCK.executeBatch(_targets, _values, _calldatas, bytes32(0), bytes32(0));
    assertTrue(
      PROTOCOL_TIMELOCK.isOperationDone(
        PROTOCOL_TIMELOCK.hashOperationBatch(_targets, _values, _calldatas, bytes32(0), bytes32(0))
      )
    );

    // OpenZeppelin v4's `AccessControl` reverts with a string naming the account and the role.
    vm.expectRevert(
      bytes(
        string.concat(
          "AccessControl: account ",
          vm.toLowercase(vm.toString(address(PROTOCOL_GOVERNOR))),
          " is missing role ",
          vm.toString(PROPOSER_ROLE)
        )
      )
    );
    vm.prank(address(PROTOCOL_GOVERNOR));
    PROTOCOL_TIMELOCK.scheduleBatch(_targets, _values, _calldatas, bytes32(0), keccak256("salt"), 0);
  }

  function testFuzz_RevertIf_TheMigrationProposalAlreadyExists(uint256 _elapsed) public {
    _dealProposerVotes();
    // Records the migration proposal the script makes, then rolls back the run, which also simulated the migration.
    uint256 _beforeRun = vm.snapshotState();
    CreatedProposal memory _proposal = _runAndRecordProposal(vetoGovernor);
    vm.revertToState(_beforeRun);
    vm.prank(DEFAULT_SENDER);
    PROTOCOL_GOVERNOR.propose(_proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description);
    // Up to just past the proposal's voting period, through its Pending, Active and Defeated states.
    vm.warp(
      block.timestamp + _bound(_elapsed, 0, PROTOCOL_GOVERNOR.votingDelay() + PROTOCOL_GOVERNOR.votingPeriod() + 1)
    );
    IGovernor.ProposalState _existingState = PROTOCOL_GOVERNOR.state(_proposal.proposalId);
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert(
      bytes(
        string.concat(
          "ProposeProtocolTimelockRoleMigration: the migration proposal already exists on ZkProtocolGovernor (",
          _proposalStateName(_existingState),
          ")"
        )
      )
    );
    _script.run();
  }

  function testFuzz_RevertIf_TheProposerIsBelowTheProposalThreshold(uint256 _votes) public {
    _dealVotes(DEFAULT_SENDER, _bound(_votes, 0, PROTOCOL_GOVERNOR.proposalThreshold() - 1));
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert(
      "ProposeProtocolTimelockRoleMigration: the proposer's votes are below ZkProtocolGovernor's threshold"
    );
    _script.run();
  }

  function testFuzz_RevertIf_TheVetoGovernorAlreadyHoldsARole(uint256 _roleIndex) public {
    _dealProposerVotes();
    _grantTimelockRole(_boundToMigratedRole(_roleIndex), vetoGovernor);
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert("ProposeProtocolTimelockRoleMigration: the Veto Governor already holds a Protocol Timelock role");
    _script.run();
  }

  function testFuzz_RevertIf_ZkProtocolGovernorDoesNotUseTheProtocolTimelock(address _otherTimelock) public {
    vm.assume(_otherTimelock != address(PROTOCOL_TIMELOCK));
    _dealProposerVotes();
    // `ZkProtocolGovernor` can only change its timelock through a proposal, so its answer is mocked.
    vm.mockCall(address(PROTOCOL_GOVERNOR), abi.encodeWithSignature("timelock()"), abi.encode(_otherTimelock));
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert("ProposeProtocolTimelockRoleMigration: ZkProtocolGovernor does not use the Protocol Timelock");
    _script.run();
  }

  function testFuzz_RevertIf_ZkProtocolGovernorIsMissingARole(uint256 _roleIndex) public {
    _dealProposerVotes();
    vm.prank(address(PROTOCOL_TIMELOCK));
    PROTOCOL_TIMELOCK.revokeRole(_boundToMigratedRole(_roleIndex), address(PROTOCOL_GOVERNOR));
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert(
      "ProposeProtocolTimelockRoleMigration: ZkProtocolGovernor is missing a Protocol Timelock role it should hold"
    );
    _script.run();
  }

  function testFuzz_RevertIf_AGovernorWouldAdministerTheTimelockAfterTheMigration(bool _vetoGovernorIsAdmin) public {
    _dealProposerVotes();
    _grantTimelockRole(TIMELOCK_ADMIN_ROLE, _vetoGovernorIsAdmin ? vetoGovernor : address(PROTOCOL_GOVERNOR));
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert("ProposeProtocolTimelockRoleMigration: a governor administers the Protocol Timelock");
    _script.run();
  }

  function testFuzz_RevertIf_ARoleIsOpenToEveryAccount(uint256 _roleIndex) public {
    _dealProposerVotes();
    _grantTimelockRole(_boundToMigratedRole(_roleIndex), address(0));
    ProposeProtocolTimelockRoleMigrationEraMainnet _script = _deployScript(vetoGovernor);

    vm.expectRevert("ProposeProtocolTimelockRoleMigration: a Protocol Timelock role is open to every account");
    _script.run();
  }
}
