// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";
import {SupermajorityGovernorChecks} from "council/script/SupermajorityGovernorChecks.sol";

// Deploys the ZKsync Supermajority Governor and its override timelock. Run this before
// `DeployZkProtocolUpgradeGovernance` in `l2-contracts/council`, which deploys the council contracts and makes this
// override timelock the Veto Governor's `vetoOverrideRole`. If that script is run from a different account, pass this
// script's deployer to it as `SUPERMAJORITY_GOVERNOR_DEPLOYER`.
//
// The Supermajority Governor is the existing `ZkProtocolGovernor`, deployed unchanged: its quorum counts FOR votes only
// and a proposal succeeds only with more FOR than AGAINST votes, which are the ZIP's supermajority rules. It and the
// override timelock are OpenZeppelin v4 contracts, so they are deployed from this project rather than the council
// project, which uses OpenZeppelin v5.
//
// The governor needs the timelock's address and the timelock needs the governor as its proposer, so the timelock is
// deployed with the deployer as a temporary admin. The deployer grants the governor the proposer and canceller roles
// and then renounces the admin role, leaving the timelock administered only by itself.
abstract contract DeploySupermajorityGovernor is SupermajorityGovernorChecks {
  ZkProtocolGovernor public governor;
  TimelockController public timelock;

  function run() public virtual {
    DeploymentParams memory _params = _deploymentParams();
    // Params the council deployment would refuse fail here, rather than after the governor is deployed.
    _validateSupermajorityGovernorParams(_params);
    _logDeploymentParams(_params);

    vm.startBroadcast();
    // The broadcasting account, read inside the broadcast so it is the deployer rather than the script contract.
    (, address _deployer,) = vm.readCallers();

    address[] memory _executors = new address[](1);
    _executors[0] = address(0);

    // BROADCAST: deploy the override timelock with the deployer as a temporary admin
    _log("[1/5] Deploying the override TimelockController");
    timelock = new TimelockController(_params.overrideTimelockMinDelay, new address[](0), _executors, _deployer);

    // BROADCAST: deploy the Supermajority Governor
    _log("[2/5] Deploying the Supermajority Governor (ZkProtocolGovernor)");
    governor = new ZkProtocolGovernor(
      _params.supermajorityGovernorName,
      IVotes(_params.zkToken),
      timelock,
      _params.supermajorityGovernorVotingDelay,
      _params.supermajorityGovernorVotingPeriod,
      _params.supermajorityGovernorProposalThreshold,
      _params.supermajorityGovernorQuorum,
      _params.supermajorityGovernorLateQuorumVoteExtension
    );

    // BROADCAST: make the governor the timelock's proposer
    _log("[3/5] Granting PROPOSER_ROLE on the override timelock to the governor");
    timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));

    // BROADCAST: make the governor the timelock's canceller
    _log("[4/5] Granting CANCELLER_ROLE on the override timelock to the governor");
    timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

    // BROADCAST: renounce the deployer's temporary admin role
    _log("[5/5] Renouncing the deployer's TIMELOCK_ADMIN_ROLE on the override timelock");
    timelock.renounceRole(timelock.TIMELOCK_ADMIN_ROLE(), _deployer);

    vm.stopBroadcast();

    _validateSupermajorityGovernorDeployment(_params, address(governor), address(timelock), _deployer);

    _log(string.concat("Supermajority Governor (SUPERMAJORITY_GOVERNOR): ", vm.toString(address(governor))));
    _log(string.concat("Override TimelockController (OVERRIDE_TIMELOCK): ", vm.toString(address(timelock))));
  }

  // Runs the same checks against an existing Supermajority Governor deployment, reading `SUPERMAJORITY_GOVERNOR`,
  // `OVERRIDE_TIMELOCK` and `DEPLOYER`, the account that ran this script.
  function check() public virtual {
    governor = ZkProtocolGovernor(payable(vm.envAddress("SUPERMAJORITY_GOVERNOR")));
    timelock = TimelockController(payable(vm.envAddress("OVERRIDE_TIMELOCK")));
    _validateSupermajorityGovernorDeployment(
      _deploymentParams(), address(governor), address(timelock), vm.envAddress("DEPLOYER")
    );
    _log("All Supermajority Governor deployment checks passed");
  }

  function _logDeploymentParams(DeploymentParams memory _params) internal view {
    _log("Deploying the Supermajority Governor with:");
    _log(string.concat("  token:                    ", vm.toString(_params.zkToken)));
    _log(string.concat("  name:                     ", _params.supermajorityGovernorName));
    _log(string.concat("  votingDelay:              ", vm.toString(_params.supermajorityGovernorVotingDelay)));
    _log(string.concat("  votingPeriod:             ", vm.toString(_params.supermajorityGovernorVotingPeriod)));
    _log(string.concat("  proposalThreshold:        ", vm.toString(_params.supermajorityGovernorProposalThreshold)));
    _log(string.concat("  quorum:                   ", vm.toString(uint256(_params.supermajorityGovernorQuorum))));
    _log(
      string.concat("  lateQuorumVoteExtension:  ", vm.toString(_params.supermajorityGovernorLateQuorumVoteExtension))
    );
    _log(string.concat("  overrideTimelockMinDelay: ", vm.toString(_params.overrideTimelockMinDelay)));
  }
}
