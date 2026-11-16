// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IZkProtocolGovernor} from "script/SupermajorityGovernorChecks.sol";
import {ZkProtocolUpgradeGovernanceChecks} from "script/ZkProtocolUpgradeGovernanceChecks.sol";

// Proposes, from the broadcasting delegate, the `ZkProtocolGovernor` proposal that moves the proposer, executor and
// canceller roles on the Protocol Timelock from `ZkProtocolGovernor` to `ZkProtocolUpgradeVetoGovernor`. The proposal
// ID depends on the exact description, so proposing from the script keeps the description on chain, and with it the ID,
// exactly as built here.
//
// The Protocol Timelock is an OpenZeppelin v4 `TimelockController` that administers itself, so the proposal's calls
// target the timelock directly and run with the timelock as `msg.sender`. All three roles are granted to the Veto
// Governor before any is revoked from `ZkProtocolGovernor`, in one proposal, so the timelock is never left without a
// proposer, executor or canceller. Revoking `EXECUTOR_ROLE` from `ZkProtocolGovernor` while it executes this proposal
// is safe, because the timelock checks the role only on entry to `executeBatch`. The timelock's minimum delay of zero
// and its self-administration are unchanged.
//
// Once the proposal executes, `ZkProtocolGovernor` can no longer queue, execute or cancel on the timelock, so any of
// its other proposals still in flight at that point are stranded.
//
// `run` checks that the deployment is fully configured, that the roles have not moved yet, that the migration has not
// been proposed already, and that the delegate's votes meet the proposal threshold. It then proposes the migration,
// simulates its execution against the live chain state, and checks the result. Checking for stranded proposals at
// execution time is a manual step: list `ZkProtocolGovernor`'s proposals and check each one's `state`.
abstract contract ProposeProtocolTimelockRoleMigration is ZkProtocolUpgradeGovernanceChecks {
  bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

  // A `ZkProtocolGovernor` proposal, in the form `propose` takes it.
  struct Proposal {
    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description;
  }

  // The governor that holds the three roles on the Protocol Timelock before the migration.
  function _protocolGovernor() internal view virtual returns (address);

  // Proposes the migration from the broadcasting delegate, and simulates and checks its execution.
  function run() public virtual {
    address _vetoGovernor = _deployedVetoGovernor();
    _checkBeforeMigration(_vetoGovernor);

    Proposal memory _proposal = _migrationProposal(_vetoGovernor);
    uint256 _proposalId = _hashProposal(_proposal);
    _checkNotAlreadyProposed(_proposalId);

    // Proposed before the simulation, which pranks `ZkProtocolGovernor` and so must stay out of the broadcast.
    vm.startBroadcast();
    // The broadcaster is the proposer. The threshold check only makes view calls, so it adds nothing to the broadcast.
    (, address _proposer,) = vm.readCallers();
    _checkProposerMeetsThreshold(_proposer);
    uint256 _proposedId = IGovernor(_protocolGovernor())
      .propose(_proposal.targets, _proposal.values, _proposal.calldatas, _proposal.description);
    vm.stopBroadcast();
    if (_proposedId != _proposalId) {
      revert("ProposeProtocolTimelockRoleMigration: ZkProtocolGovernor returned an unexpected proposal ID");
    }

    _simulateMigration(_proposal);
    _checkAfterMigration(_vetoGovernor);

    _log(string.concat("Proposal ID: ", vm.toString(bytes32(_proposalId))));
    _log(string.concat("Governor: ", vm.toString(_protocolGovernor())));
    _log(string.concat("Proposed by: ", vm.toString(_proposer)));
    _log("Simulated execution: all migration checks passed");
  }

  // The Protocol Timelock, the timelock the Veto Governor queues and executes through.
  function _protocolTimelock() internal view returns (TimelockController) {
    return TimelockController(payable(_deploymentParams().protocolTimelock));
  }

  // The Veto Governor that receives the roles, read from `VETO_GOVERNOR`.
  function _deployedVetoGovernor() internal view virtual returns (address) {
    return vm.envAddress("VETO_GOVERNOR");
  }

  // Runs every deployment check against the deployed council governance, reading its addresses and their deployer from
  // `COUNCIL_TOKEN`, `COUNCIL_GOVERNOR`, `VETO_GOVERNOR`, `SUPERMAJORITY_GOVERNOR`, `OVERRIDE_TIMELOCK` and `DEPLOYER`.
  // The Supermajority Governor's deployer is read from `SUPERMAJORITY_GOVERNOR_DEPLOYER`, which defaults to `DEPLOYER`.
  function _validateExistingDeployment() internal view virtual {
    address _deployer = vm.envAddress("DEPLOYER");
    _validateDeployment(
      _deploymentParams(), _deploymentFromEnv(), _deployer, vm.envOr("SUPERMAJORITY_GOVERNOR_DEPLOYER", _deployer)
    );
  }

  // Builds the migration proposal: grant the three roles to the Veto Governor, then revoke them from
  // `ZkProtocolGovernor`.
  function _migrationProposal(address _vetoGovernor) internal view returns (Proposal memory _proposal) {
    address _timelock = address(_protocolTimelock());
    bytes32[3] memory _roles = _migratedRoles();
    _proposal.targets = new address[](6);
    _proposal.values = new uint256[](6);
    _proposal.calldatas = new bytes[](6);
    for (uint256 _i = 0; _i < 3; _i += 1) {
      _proposal.targets[_i] = _timelock;
      _proposal.calldatas[_i] = abi.encodeCall(IAccessControl.grantRole, (_roles[_i], _vetoGovernor));
      _proposal.targets[_i + 3] = _timelock;
      _proposal.calldatas[_i + 3] = abi.encodeCall(IAccessControl.revokeRole, (_roles[_i], _protocolGovernor()));
    }
    _proposal.description = _migrationDescription(_vetoGovernor);
  }

  // The description of the migration proposal. It is part of the proposal ID, so it depends only on the addresses
  // involved.
  function _migrationDescription(address _vetoGovernor) internal view returns (string memory) {
    return string.concat(
      "# Move Protocol Timelock roles to the ZKsync Protocol Upgrade Veto Governor\n\n",
      "Grants PROPOSER_ROLE, EXECUTOR_ROLE and CANCELLER_ROLE on the Protocol Timelock (",
      vm.toString(address(_protocolTimelock())),
      ") to ZkProtocolUpgradeVetoGovernor (",
      vm.toString(_vetoGovernor),
      "), then revokes the same roles from ZkProtocolGovernor (",
      vm.toString(_protocolGovernor()),
      "). After this proposal executes, protocol upgrades are proposed through the ZKsync Protocol Upgrade Council ",
      "and the Veto Governor instead of ZkProtocolGovernor. The timelock's minimum delay and administration are unchanged."
    );
  }

  // The ID `ZkProtocolGovernor` assigns to a proposal.
  function _hashProposal(Proposal memory _proposal) internal view returns (uint256) {
    return IGovernor(_protocolGovernor())
      .hashProposal(_proposal.targets, _proposal.values, _proposal.calldatas, keccak256(bytes(_proposal.description)));
  }

  // Checks the state the migration starts from: the council governance is fully deployed and configured,
  // `ZkProtocolGovernor` uses the Protocol Timelock and holds the three roles, the Veto Governor holds none, and the
  // timelock administers itself with no delay.
  function _checkBeforeMigration(address _vetoGovernor) internal view {
    _validateExistingDeployment();

    TimelockController _timelock = _protocolTimelock();
    if (IZkProtocolGovernor(_protocolGovernor()).timelock() != address(_timelock)) {
      revert("ProposeProtocolTimelockRoleMigration: ZkProtocolGovernor does not use the Protocol Timelock");
    }
    bytes32[3] memory _roles = _migratedRoles();
    for (uint256 _i = 0; _i < 3; _i += 1) {
      if (!_timelock.hasRole(_roles[_i], _protocolGovernor())) {
        revert(
          "ProposeProtocolTimelockRoleMigration: ZkProtocolGovernor is missing a Protocol Timelock role it should hold"
        );
      }
      if (_timelock.hasRole(_roles[_i], _vetoGovernor)) {
        revert("ProposeProtocolTimelockRoleMigration: the Veto Governor already holds a Protocol Timelock role");
      }
    }
    _checkProtocolTimelockSettings();
  }

  // Checks the state the migration ends in: the Veto Governor holds the three roles, `ZkProtocolGovernor` holds none,
  // neither administers the timelock, and the timelock still administers itself with no delay.
  function _checkAfterMigration(address _vetoGovernor) internal view {
    TimelockController _timelock = _protocolTimelock();
    bytes32[3] memory _roles = _migratedRoles();
    for (uint256 _i = 0; _i < 3; _i += 1) {
      if (!_timelock.hasRole(_roles[_i], _vetoGovernor)) {
        revert(
          "ProposeProtocolTimelockRoleMigration: after the migration, the Veto Governor lacks a Protocol Timelock role"
        );
      }
      if (_timelock.hasRole(_roles[_i], _protocolGovernor())) {
        revert(
          "ProposeProtocolTimelockRoleMigration: after the migration, ZkProtocolGovernor still holds a timelock role"
        );
      }
    }
    if (
      _timelock.hasRole(TIMELOCK_ADMIN_ROLE, _protocolGovernor())
        || _timelock.hasRole(TIMELOCK_ADMIN_ROLE, _vetoGovernor)
    ) {
      revert("ProposeProtocolTimelockRoleMigration: a governor administers the Protocol Timelock");
    }
    _checkProtocolTimelockSettings();
  }

  // Checks the Protocol Timelock settings the migration leaves unchanged: no minimum delay, self-administration, and
  // none of the three roles open to every account.
  function _checkProtocolTimelockSettings() internal view {
    TimelockController _timelock = _protocolTimelock();
    if (_timelock.getMinDelay() != 0) {
      revert("ProposeProtocolTimelockRoleMigration: the Protocol Timelock's minimum delay is not 0");
    }
    if (!_timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(_timelock))) {
      revert("ProposeProtocolTimelockRoleMigration: the Protocol Timelock does not administer itself");
    }
    bytes32[3] memory _roles = _migratedRoles();
    for (uint256 _i = 0; _i < 3; _i += 1) {
      if (_timelock.hasRole(_roles[_i], address(0))) {
        revert("ProposeProtocolTimelockRoleMigration: a Protocol Timelock role is open to every account");
      }
    }
  }

  // Checks that the migration proposal does not exist on `ZkProtocolGovernor` yet, since proposing it again reverts. A
  // proposal exists once it has a snapshot.
  function _checkNotAlreadyProposed(uint256 _migrationProposalId) internal view {
    IGovernor _governor = IGovernor(_protocolGovernor());
    if (_governor.proposalSnapshot(_migrationProposalId) == 0) {
      return;
    }
    string[8] memory _stateNames =
      ["Pending", "Active", "Canceled", "Defeated", "Succeeded", "Queued", "Expired", "Executed"];
    IGovernor.ProposalState _state = _governor.state(_migrationProposalId);
    revert(
      string.concat(
        "ProposeProtocolTimelockRoleMigration: the migration proposal already exists on ZkProtocolGovernor (",
        _stateNames[uint8(_state)],
        ")"
      )
    );
  }

  // Checks that `_proposer` has the votes `ZkProtocolGovernor` requires to propose, counted one tick before the
  // governor's current clock as the governor counts them. The clock is the ZK token's, which counts timestamps.
  function _checkProposerMeetsThreshold(address _proposer) internal view {
    IGovernor _governor = IGovernor(_protocolGovernor());
    if (_governor.getVotes(_proposer, _governor.clock() - 1) < _governor.proposalThreshold()) {
      revert("ProposeProtocolTimelockRoleMigration: the proposer's votes are below ZkProtocolGovernor's threshold");
    }
  }

  // Executes the migration proposal on the current chain state the way `ZkProtocolGovernor` does once it passes: as a
  // timelock batch, scheduled when the proposal is queued and then executed by the governor. For simulation only: it
  // pranks `ZkProtocolGovernor`, so it must not run while broadcasting.
  function _simulateMigration(Proposal memory _proposal) internal {
    TimelockController _timelock = _protocolTimelock();
    bytes32 _salt = keccak256(bytes(_proposal.description));
    vm.prank(_protocolGovernor());
    _timelock.scheduleBatch(_proposal.targets, _proposal.values, _proposal.calldatas, bytes32(0), _salt, 0);
    vm.prank(_protocolGovernor());
    _timelock.executeBatch(_proposal.targets, _proposal.values, _proposal.calldatas, bytes32(0), _salt);
  }

  // The roles the migration moves, in the order they are granted and revoked.
  function _migratedRoles() internal pure returns (bytes32[3] memory) {
    return [PROPOSER_ROLE, EXECUTOR_ROLE, CANCELLER_ROLE];
  }
}
