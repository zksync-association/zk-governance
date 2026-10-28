// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";
import {BasicCouncilVetoGovernor} from "council-governance/BasicCouncilVetoGovernor.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";
import {ZkProtocolUpgradeVetoGovernor} from "src/ZkProtocolUpgradeVetoGovernor.sol";
import {ZkProtocolUpgradeGovernanceChecks} from "script/ZkProtocolUpgradeGovernanceChecks.sol";

// Run after `DeploySupermajorityGovernor` in the main l2-contracts project, which deploys the Supermajority Governor
// and its override timelock and checks their own parameters. Deploys `CouncilERC20`, `ZkProtocolUpgradeCouncilGovernor`
// and `ZkProtocolUpgradeVetoGovernor`, wires the Veto Governor to that override timelock, hands every admin role to the
// governance admin, and then checks the whole deployment. The checks confirm that neither this script's deployer nor
// the Supermajority Governor's deployer kept privileges on any contract. The Supermajority Governor's deployer is read
// from `SUPERMAJORITY_GOVERNOR_DEPLOYER`, which defaults to this script's broadcaster, and is checked for leftover
// roles on the override timelock.
//
// `run` reads the Supermajority Governor and override timelock addresses from the `SUPERMAJORITY_GOVERNOR` and
// `OVERRIDE_TIMELOCK` environment variables, and optionally `SUPERMAJORITY_GOVERNOR_DEPLOYER`. `check` runs the same
// checks against an existing deployment, reading `COUNCIL_TOKEN`, `COUNCIL_GOVERNOR`, `VETO_GOVERNOR`,
// `SUPERMAJORITY_GOVERNOR`, `OVERRIDE_TIMELOCK`, `DEPLOYER` and optionally `SUPERMAJORITY_GOVERNOR_DEPLOYER`, which
// defaults to `DEPLOYER`.
//
// The contracts reference each other, so they are deployed first and wired afterwards, rather than by predicting
// addresses, which ZKsync Era derives differently from the EVM:
// - The Council Governor is deployed with no Veto Governor and the deployer as a temporary admin. The Veto Governor
//   stores the Council Governor's address immutably, so it is deployed next; the deployer then points the Council
//   Governor at it and transfers the admin role.
// - `CouncilERC20` is owned by the deployer only while seats are minted.
abstract contract DeployZkProtocolUpgradeGovernance is ZkProtocolUpgradeGovernanceChecks {
  CouncilERC20 public councilToken;
  ZkProtocolUpgradeCouncilGovernor public councilGovernor;
  ZkProtocolUpgradeVetoGovernor public vetoGovernor;

  function run() public virtual {
    DeploymentParams memory _params = _deploymentParams();
    Deployment memory _deployment;
    (_deployment.supermajorityGovernor, _deployment.overrideTimelock) = _supermajorityGovernorContracts();
    _validateDeploymentParams(_params);

    // The broadcasting account, read inside a broadcast so it is the deployer rather than the script contract.
    vm.startBroadcast();
    (, address _deployer,) = vm.readCallers();
    vm.stopBroadcast();
    address _supermajorityGovernorDeployerAccount = _supermajorityGovernorDeployer(_deployer);
    _logDeploymentParams(_params, _deployment, _supermajorityGovernorDeployerAccount);

    // Fail before deploying anything if the Supermajority Governor or override timelock is wrong. Once the Veto
    // Governor is deployed, replacing its override timelock takes a full ZIP, since only the governance admin can call
    // `setVetoOverrideRole`.
    _validateSupermajorityGovernorDeployment(
      _params,
      _deployment.supermajorityGovernor,
      address(_deployment.overrideTimelock),
      _supermajorityGovernorDeployerAccount
    );

    vm.startBroadcast();
    _deployCouncilToken(_params, _deployer);
    _deployCouncilAndVetoGovernors(_params, _deployment, _deployer);
    vm.stopBroadcast();

    _deployment.councilToken = councilToken;
    _deployment.councilGovernor = councilGovernor;
    _deployment.vetoGovernor = vetoGovernor;
    _validateDeployment(_params, _deployment, _deployer, _supermajorityGovernorDeployerAccount);

    _log(string.concat("CouncilERC20 (COUNCIL_TOKEN): ", vm.toString(address(councilToken))));
    _log(string.concat("ZkProtocolUpgradeCouncilGovernor (COUNCIL_GOVERNOR): ", vm.toString(address(councilGovernor))));
    _log(string.concat("ZkProtocolUpgradeVetoGovernor (VETO_GOVERNOR): ", vm.toString(address(vetoGovernor))));
  }

  function check() public view virtual {
    address _deployer = vm.envAddress("DEPLOYER");
    _validateDeployment(_deploymentParams(), _deploymentFromEnv(), _deployer, _supermajorityGovernorDeployer(_deployer));
    _log("All deployment checks passed");
  }

  // The Supermajority Governor and override timelock, read from `SUPERMAJORITY_GOVERNOR` and `OVERRIDE_TIMELOCK`.
  function _supermajorityGovernorContracts()
    internal
    view
    virtual
    returns (address _supermajorityGovernor, TimelockController _overrideTimelock)
  {
    _supermajorityGovernor = vm.envAddress("SUPERMAJORITY_GOVERNOR");
    _overrideTimelock = TimelockController(payable(vm.envAddress("OVERRIDE_TIMELOCK")));
  }

  // The account that deployed the Supermajority Governor and override timelock, read from
  // `SUPERMAJORITY_GOVERNOR_DEPLOYER`, or `_default` if it is unset.
  function _supermajorityGovernorDeployer(address _default) internal view virtual returns (address) {
    return vm.envOr("SUPERMAJORITY_GOVERNOR_DEPLOYER", _default);
  }

  // Rejects params that the deployment itself would accept but that leave the governance unusable. Mistakes that make
  // a deployment call revert, such as a duplicate or zero council member, already fail the simulation.
  function _validateDeploymentParams(DeploymentParams memory _params) internal view {
    _validateSupermajorityGovernorParams(_params);
    if (_params.protocolTimelock.code.length == 0) {
      revert("DeployZkProtocolUpgradeGovernance: protocolTimelock has no code; set it to the Protocol Timelock");
    }
    if (_params.governanceAdmin == address(0)) {
      revert("DeployZkProtocolUpgradeGovernance: governanceAdmin is the zero address");
    }
    if (_params.councilMembers.length == 0) {
      revert("DeployZkProtocolUpgradeGovernance: councilMembers is empty");
    }
    if (_params.vetoGovernorVetoGuardian == address(0)) {
      revert("DeployZkProtocolUpgradeGovernance: vetoGovernorVetoGuardian is the zero address; set the veto guardian");
    }
    if (_params.councilGovernorProposalThreshold > _params.votesPerCouncilSeat) {
      revert(
        "DeployZkProtocolUpgradeGovernance: councilGovernorProposalThreshold is above one seat; no member could propose"
      );
    }
  }

  function _logDeploymentParams(
    DeploymentParams memory _params,
    Deployment memory _deployment,
    address _supermajorityGovernorDeployerAccount
  ) internal view {
    _log("Deploying the protocol upgrade council governance with:");
    _log(string.concat("  zkToken:               ", vm.toString(_params.zkToken)));
    _log(string.concat("  protocolTimelock:      ", vm.toString(_params.protocolTimelock)));
    _log(string.concat("  governanceAdmin:       ", vm.toString(_params.governanceAdmin)));
    _log(string.concat("  supermajorityGovernor: ", vm.toString(_deployment.supermajorityGovernor)));
    _log(string.concat("  overrideTimelock:      ", vm.toString(address(_deployment.overrideTimelock))));
    _log(string.concat("  supermajorityDeployer: ", vm.toString(_supermajorityGovernorDeployerAccount)));
    _log(string.concat("  vetoThreshold:         ", vm.toString(_params.vetoGovernorVetoThreshold)));
    _log(string.concat("  council members:       ", vm.toString(_params.councilMembers.length)));
    for (uint256 _i = 0; _i < _params.councilMembers.length; _i += 1) {
      _log(string.concat("    ", vm.toString(_params.councilMembers[_i])));
    }
  }

  // Deploys `CouncilERC20`, mints one seat to each council member, and hands ownership to the governance admin.
  function _deployCouncilToken(DeploymentParams memory _params, address _deployer) internal {
    // BROADCAST: deploy CouncilERC20 with the deployer as a temporary owner
    _log("[1/7] Deploying CouncilERC20");
    councilToken =
      new CouncilERC20(_params.councilTokenName, _params.councilTokenSymbol, _deployer, _params.votesPerCouncilSeat);

    for (uint256 _i = 0; _i < _params.councilMembers.length; _i += 1) {
      // BROADCAST: mint one seat to each council member
      _log(string.concat("[2/7] Minting a seat to ", vm.toString(_params.councilMembers[_i])));
      councilToken.mint(_params.councilMembers[_i], _params.votesPerCouncilSeat);
    }

    // BROADCAST: hand CouncilERC20 ownership to the governance admin
    _log(string.concat("[3/7] Transferring CouncilERC20 ownership to ", vm.toString(_params.governanceAdmin)));
    councilToken.transferOwnership(_params.governanceAdmin);
  }

  // Deploys the Council and Veto Governors, points the Council Governor at the Veto Governor, and hands the Council
  // Governor's admin role to the governance admin.
  function _deployCouncilAndVetoGovernors(
    DeploymentParams memory _params,
    Deployment memory _deployment,
    address _deployer
  ) internal {
    // BROADCAST: deploy the Council Governor with no Veto Governor and the deployer as a temporary admin
    _log("[4/7] Deploying ZkProtocolUpgradeCouncilGovernor");
    councilGovernor = new ZkProtocolUpgradeCouncilGovernor(
      _params.councilGovernorName,
      councilToken,
      IGovernor(address(0)),
      _deployer,
      BasicCouncilGovernor.InitialCouncilParams({
        initialVotingDelay: _params.councilGovernorVotingDelay,
        initialVotingPeriod: _params.councilGovernorVotingPeriod,
        initialProposalThreshold: _params.councilGovernorProposalThreshold,
        // Quorum and super-quorum are fixed at one seat; the governor accepts only zero fractions.
        initialQuorumFraction: 0,
        initialSuperQuorumFraction: 0
      })
    );

    // BROADCAST: deploy the Veto Governor
    _log("[5/7] Deploying ZkProtocolUpgradeVetoGovernor");
    vetoGovernor = new ZkProtocolUpgradeVetoGovernor(
      BasicCouncilVetoGovernor.ConstructorParams({
        name: _params.vetoGovernorName,
        token: _params.zkToken,
        votingDelay: _params.vetoGovernorVotingDelay,
        votingPeriod: _params.vetoGovernorVotingPeriod,
        proposalThreshold: _params.vetoGovernorProposalThreshold,
        vetoGuardian: _params.vetoGovernorVetoGuardian,
        vetoOverrideRole: address(_deployment.overrideTimelock),
        vetoOverrideDuration: _params.vetoGovernorVetoOverrideDuration,
        votingPeriodExtension: _params.vetoGovernorVotingPeriodExtension,
        votingPeriodExtensionThresholdPct: _params.vetoGovernorVotingPeriodExtensionThresholdPct,
        // The veto threshold is set in votes; the governor accepts only a zero fraction.
        vetoThresholdNumerator: 0,
        timelock: TimelockController(payable(_params.protocolTimelock)),
        governorAdmin: _params.governanceAdmin,
        council: address(councilGovernor)
      }),
      _params.vetoGovernorVetoThreshold
    );

    // BROADCAST: point the Council Governor at the Veto Governor
    _log("[6/7] Setting the Council Governor's Veto Governor");
    councilGovernor.setCouncilVetoGovernor(IGovernor(address(vetoGovernor)));

    // BROADCAST: hand the Council Governor's admin role to the governance admin
    _log(
      string.concat("[7/7] Transferring the Council Governor's admin role to ", vm.toString(_params.governanceAdmin))
    );
    councilGovernor.transferOwnership(_params.governanceAdmin);
  }
}
