// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ZkProtocolUpgradeDeploymentConfig} from "./ZkProtocolUpgradeDeploymentConfig.sol";

// The ZIP parameters for ZKsync Era mainnet. Durations are in seconds, since the ZK token and `CouncilERC20` both use a
// timestamp clock, and token amounts are in base units (18 decimals).
abstract contract ZkProtocolUpgradeEraMainnetConfig is ZkProtocolUpgradeDeploymentConfig {
  address internal constant ZK_TOKEN = 0x5A7d6b2F92C77FAD6CCaBd7EE0624E64907Eaf3E;
  address internal constant PROTOCOL_TIMELOCK = 0x085b8B6407f150D62adB1EF926F7f304600ec714;

  // The ProtocolUpgradeHandler on Ethereum mainnet. The governance admin is its L1-to-L2 aliased address.
  address internal constant L1_PROTOCOL_UPGRADE_HANDLER = 0xE30Dca3047B37dc7d88849dE4A4Dc07937ad5Ab3;
  address internal constant GOVERNANCE_ADMIN = 0xF41EcA3047B37dc7d88849de4a4dc07937Ad6bc4;

  // The offset ZKsync adds to an L1 contract's address when it sends an L1-to-L2 transaction.
  uint160 internal constant L1_TO_L2_ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);

  // `view` rather than `pure`, so a test configuration can override it to swap in test doubles.
  function _deploymentParams() internal view virtual override returns (DeploymentParams memory) {
    if (GOVERNANCE_ADMIN != _applyL1ToL2Alias(L1_PROTOCOL_UPGRADE_HANDLER)) {
      revert("ZkProtocolUpgradeEraMainnetConfig: GOVERNANCE_ADMIN is not the aliased L1 ProtocolUpgradeHandler");
    }

    address[] memory _councilMembers = new address[](8);
    _councilMembers[0] = 0xe38dc029623f0af56BdC46E5318610E257d6b760; // Matter Labs
    _councilMembers[1] = 0x870Ec9631E28ee6C8b304e238E9b6890a99ab8aA; // Nethermind
    _councilMembers[2] = 0x305798C076B64Be35Aa6367C6632b79e29D0113A; // OpenZeppelin
    _councilMembers[3] = 0x356cF4Ac9fA86F0a9dDdc62e48082FE5Cd14bE7b; // Spearbit
    _councilMembers[4] = 0x3043bF9c9A512d20Dda2c2b2C3D69AF6f7Fcd5B1; // Chainlight
    _councilMembers[5] = 0x9BC8d216d63b38c390e465D664FEb63B67659c13; // Cyfrin
    _councilMembers[6] = 0xdbc2E250cBA867D6619Bed342Ca3Eca7b71e8b82; // Dedaub
    _councilMembers[7] = 0x46fc9a8A72456c84F42c5c9e5df46984c0078B15; // Peckshield

    return DeploymentParams({
      zkToken: ZK_TOKEN,
      protocolTimelock: PROTOCOL_TIMELOCK,
      governanceAdmin: GOVERNANCE_ADMIN,
      councilTokenName: "ZKsync Protocol Upgrade Council Seat",
      councilTokenSymbol: "ZKPUC",
      votesPerCouncilSeat: 1e18,
      councilMembers: _councilMembers,
      councilGovernorName: "ZKsync Protocol Upgrade Council",
      councilGovernorVotingDelay: 1 days,
      councilGovernorVotingPeriod: 3 days,
      // One seat, so any member can propose.
      councilGovernorProposalThreshold: 1e18,
      vetoGovernorName: "ZKsync Protocol Upgrade Veto Governor",
      vetoGovernorVotingDelay: 1 days,
      vetoGovernorVotingPeriod: 7 days,
      // Zero, since only the Council Governor can propose to the Veto Governor.
      vetoGovernorProposalThreshold: 0,
      vetoGovernorVetoThreshold: 630_000_000e18,
      vetoGovernorVotingPeriodExtension: 2 days,
      // 50% of the 630M ZK veto threshold is 315M ZK.
      vetoGovernorVotingPeriodExtensionThresholdPct: 50,
      vetoGovernorVetoGuardian: 0xF197677d63BF6E2841F5108b8dFd2FD6eCEff74B,
      vetoGovernorVetoOverrideDuration: 14 days,
      supermajorityGovernorName: "ZKsync Supermajority Governor",
      supermajorityGovernorVotingDelay: 1 days,
      supermajorityGovernorVotingPeriod: 7 days,
      supermajorityGovernorProposalThreshold: 21_000_000e18,
      supermajorityGovernorQuorum: 1_260_000_000e18,
      supermajorityGovernorLateQuorumVoteExtension: 3 days,
      overrideTimelockMinDelay: 1 days
    });
  }

  function _applyL1ToL2Alias(address _l1Address) internal pure returns (address) {
    unchecked {
      return address(uint160(_l1Address) + L1_TO_L2_ALIAS_OFFSET);
    }
  }
}
