// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts-v5/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts-v5/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts-v5/governance/extensions/GovernorCountingSimple.sol";
import {IERC5805} from "@openzeppelin/contracts-v5/interfaces/IERC5805.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";

/// @title ZkProtocolUpgradeCouncilGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @notice The ZKsync Protocol Upgrade Council governor. Council members holding `CouncilERC20` seats propose protocol
/// upgrades, and a single member voting FOR is enough to sponsor a proposal and forward it to the
/// `ZkProtocolUpgradeVetoGovernor`, where token holders may veto it.
/// @dev Identical to the upstream `BasicCouncilGovernor` except for the vote success rule. Upstream uses
/// `GovernorCountingSimple`, under which a proposal succeeds only if FOR votes strictly exceed AGAINST votes, so a
/// second member voting AGAINST could block a sponsor. This governor instead treats a proposal as successful once its
/// FOR votes alone meet quorum, regardless of AGAINST and ABSTAIN votes. With 1e18-weight seats and a quorum and
/// super-quorum fraction of at most one seat (12% of eight seats), one FOR vote therefore:
/// - satisfies quorum (`GovernorCountingSimple._quorumReached`, which counts FOR plus ABSTAIN votes);
/// - satisfies vote success (this contract's `_voteSucceeded`);
/// - satisfies super-quorum, so `GovernorSuperQuorum.state` reports `Succeeded` immediately, before the deadline.
/// A proposal with no FOR votes is `Defeated` once its voting period ends.
/// @custom:security-contact security@zksync.io
contract ZkProtocolUpgradeCouncilGovernor is BasicCouncilGovernor {
  /// @param _name The name used as the EIP712 signing domain.
  /// @param _token The `CouncilERC20` seat token used to vote on proposals.
  /// @param _councilVetoGovernor The veto governor that successful proposals are forwarded to.
  /// @param _governorAdmin The address authorized to change governor parameters.
  /// @param _params The initial voting delay, voting period, proposal threshold, quorum and super-quorum fractions.
  constructor(
    string memory _name,
    IERC5805 _token,
    IGovernor _councilVetoGovernor,
    address _governorAdmin,
    InitialCouncilParams memory _params
  ) BasicCouncilGovernor(_name, _token, _councilVetoGovernor, _governorAdmin, _params) {}

  /// @inheritdoc GovernorCountingSimple
  /// @dev Succeeds when FOR votes are non-zero and alone meet quorum at the proposal snapshot. AGAINST and ABSTAIN
  /// votes are ignored, so one FOR seat cannot be outvoted by other seats. The non-zero check prevents a proposal with
  /// no votes from succeeding if quorum is ever zero, e.g. when no seats exist at the snapshot.
  function _voteSucceeded(uint256 _proposalId)
    internal
    view
    virtual
    override(Governor, GovernorCountingSimple)
    returns (bool)
  {
    (, uint256 _forVotes,) = proposalVotes(_proposalId);
    return _forVotes > 0 && _forVotes >= quorum(proposalSnapshot(_proposalId));
  }
}
