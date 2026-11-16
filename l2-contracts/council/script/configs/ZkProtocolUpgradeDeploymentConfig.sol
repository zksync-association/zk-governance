// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// The parameters of the ZKsync protocol upgrade governance deployment, shared by both deploy scripts:
// `DeploySupermajorityGovernor` in the main l2-contracts project (solc 0.8.24, OpenZeppelin v4) and
// `DeployZkProtocolUpgradeGovernance` in `l2-contracts/council` (solc 0.8.30, OpenZeppelin v5). It compiles under both,
// so it uses only plain types. A concrete configuration such as `ZkProtocolUpgradeEraMainnetConfig` supplies the
// values.
//
// The Supermajority Governor and override timelock addresses are outputs of `DeploySupermajorityGovernor`, so they are
// not params: `DeployZkProtocolUpgradeGovernance` reads them from the environment.
abstract contract ZkProtocolUpgradeDeploymentConfig {
  struct DeploymentParams {
    // Existing contracts.
    address zkToken;
    // The timelock the Veto Governor queues and executes protocol upgrades through.
    address protocolTimelock;
    // Administers the Council Governor, the Veto Governor and `CouncilERC20`.
    address governanceAdmin;
    // CouncilERC20. Each member is minted exactly one seat, which is also the per-member maximum.
    string councilTokenName;
    string councilTokenSymbol;
    uint256 votesPerCouncilSeat;
    address[] councilMembers;
    // ZkProtocolUpgradeCouncilGovernor. Its quorum and super-quorum are fixed at one seat.
    string councilGovernorName;
    uint48 councilGovernorVotingDelay;
    uint32 councilGovernorVotingPeriod;
    uint256 councilGovernorProposalThreshold;
    // ZkProtocolUpgradeVetoGovernor. The extension threshold is a percentage of the veto threshold.
    string vetoGovernorName;
    uint48 vetoGovernorVotingDelay;
    uint32 vetoGovernorVotingPeriod;
    uint256 vetoGovernorProposalThreshold;
    uint256 vetoGovernorVetoThreshold;
    uint48 vetoGovernorVotingPeriodExtension;
    uint16 vetoGovernorVotingPeriodExtensionThresholdPct;
    address vetoGovernorVetoGuardian;
    uint48 vetoGovernorVetoOverrideDuration;
    // The Supermajority Governor (`ZkProtocolGovernor`); the types match its constructor.
    string supermajorityGovernorName;
    uint48 supermajorityGovernorVotingDelay;
    uint32 supermajorityGovernorVotingPeriod;
    uint256 supermajorityGovernorProposalThreshold;
    uint224 supermajorityGovernorQuorum;
    uint64 supermajorityGovernorLateQuorumVoteExtension;
    // The override timelock, an OpenZeppelin v4 `TimelockController`.
    uint256 overrideTimelockMinDelay;
  }

  // The admin role of an OpenZeppelin v4 `TimelockController`, which v5 replaced with `DEFAULT_ADMIN_ROLE`. The
  // override timelock and the Protocol Timelock are both v4 timelocks.
  bytes32 internal constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");

  function _deploymentParams() internal view virtual returns (DeploymentParams memory);
}
