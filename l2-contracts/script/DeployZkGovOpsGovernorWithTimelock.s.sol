// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ZkGovOpsGovernor} from "src/ZkGovOpsGovernor.sol";

/// @notice Deploys, as part of the Guardians removal, a new ZkGovOpsGovernor together with a new
/// TimelockController, the same way the governors were replaced in ZIP-5: the GovOps timelock holds
/// no assets or roles, so nothing has to be migrated from the current timelock. The new pair copies
/// every setting of the current one, except the veto seat, which goes to the ZK Foundation Safe on Era.
///
/// The deployer only holds the timelock admin role during the deployment: it grants the proposer,
/// canceller and executor roles to the new governor and renounces the admin role, leaving the
/// timelock administered by itself only.
///
/// Usage:
///   CURRENT_GOVERNOR=<live ZkGovOpsGovernor> NEW_VETO_GUARDIAN=<ZK Foundation Safe on Era> \
///   FOUNDRY_PROFILE=governors-deploy forge script \
///     script/DeployZkGovOpsGovernorWithTimelock.s.sol:DeployZkGovOpsGovernorWithTimelock \
///     --zksync --rpc-url <ERA_RPC> --broadcast --private-key <deployer>
contract DeployZkGovOpsGovernorWithTimelock is Script {
  bytes32 constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
  bytes32 constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
  bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
  bytes32 constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  function run() external {
    ZkGovOpsGovernor _currentGovernor = ZkGovOpsGovernor(payable(vm.envAddress("CURRENT_GOVERNOR")));
    address _vetoGuardian = vm.envAddress("NEW_VETO_GUARDIAN");
    require(_vetoGuardian.code.length != 0, "NEW_VETO_GUARDIAN must be a contract (multisig) on Era");

    vm.startBroadcast();
    (, address _deployer,) = vm.readCallers();
    (TimelockController _timelock, ZkGovOpsGovernor _governor) = deploy(_currentGovernor, _vetoGuardian, _deployer);
    vm.stopBroadcast();

    console2.log("New TimelockController:", address(_timelock));
    console2.log("New ZkGovOpsGovernor:", address(_governor));
  }

  /// @param _currentGovernor The live ZkGovOpsGovernor whose settings are copied.
  /// @param _vetoGuardian The address taking the veto seat of the new governor.
  /// @param _deployer The address sending the deployment transactions, the temporary timelock admin.
  function deploy(ZkGovOpsGovernor _currentGovernor, address _vetoGuardian, address _deployer)
    public
    returns (TimelockController _timelock, ZkGovOpsGovernor _governor)
  {
    TimelockController _currentTimelock = TimelockController(payable(_currentGovernor.timelock()));

    _timelock = new TimelockController(_currentTimelock.getMinDelay(), new address[](0), new address[](0), _deployer);
    _governor = new ZkGovOpsGovernor(
      ZkGovOpsGovernor.ConstructorParams({
        name: _currentGovernor.name(),
        token: IVotes(address(_currentGovernor.token())),
        timelock: _timelock,
        initialVotingDelay: uint48(_currentGovernor.votingDelay()),
        initialVotingPeriod: uint32(_currentGovernor.votingPeriod()),
        initialProposalThreshold: _currentGovernor.proposalThreshold(),
        initialQuorum: uint224(_currentGovernor.quorum(_currentGovernor.clock())),
        initialVoteExtension: _currentGovernor.lateQuorumVoteExtension(),
        vetoGuardian: _vetoGuardian
      })
    );

    _timelock.grantRole(PROPOSER_ROLE, address(_governor));
    _timelock.grantRole(CANCELLER_ROLE, address(_governor));
    _timelock.grantRole(EXECUTOR_ROLE, address(_governor));
    _timelock.renounceRole(TIMELOCK_ADMIN_ROLE, _deployer);

    _checkDeployment(_currentGovernor, _currentTimelock, _timelock, _governor, _vetoGuardian, _deployer);
  }

  function _checkDeployment(
    ZkGovOpsGovernor _currentGovernor,
    TimelockController _currentTimelock,
    TimelockController _timelock,
    ZkGovOpsGovernor _governor,
    address _vetoGuardian,
    address _deployer
  ) internal view {
    // The timelock is configured like the current one and administered by itself only.
    require(_timelock.getMinDelay() == _currentTimelock.getMinDelay(), "min delay mismatch");
    require(_timelock.hasRole(TIMELOCK_ADMIN_ROLE, address(_timelock)), "timelock is not self-administered");
    require(!_timelock.hasRole(TIMELOCK_ADMIN_ROLE, _deployer), "deployer is still the timelock admin");
    require(_timelock.hasRole(PROPOSER_ROLE, address(_governor)), "governor is not a proposer");
    require(_timelock.hasRole(CANCELLER_ROLE, address(_governor)), "governor is not a canceller");
    require(_timelock.hasRole(EXECUTOR_ROLE, address(_governor)), "governor is not an executor");
    require(!_timelock.hasRole(EXECUTOR_ROLE, address(0)), "execution must not be open");

    // The governor copies every setting but the veto seat and the timelock.
    require(keccak256(bytes(_governor.name())) == keccak256(bytes(_currentGovernor.name())), "name mismatch");
    require(address(_governor.token()) == address(_currentGovernor.token()), "token mismatch");
    require(_governor.timelock() == address(_timelock), "timelock mismatch");
    require(_governor.votingDelay() == _currentGovernor.votingDelay(), "voting delay mismatch");
    require(_governor.votingPeriod() == _currentGovernor.votingPeriod(), "voting period mismatch");
    require(_governor.proposalThreshold() == _currentGovernor.proposalThreshold(), "proposal threshold mismatch");
    require(_governor.quorum(_governor.clock()) == _currentGovernor.quorum(_currentGovernor.clock()), "quorum mismatch");
    require(
      _governor.lateQuorumVoteExtension() == _currentGovernor.lateQuorumVoteExtension(), "vote extension mismatch"
    );
    require(_governor.VETO_GUARDIAN() == _vetoGuardian, "veto guardian mismatch");
  }
}
