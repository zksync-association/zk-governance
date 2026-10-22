// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";

/// @title ZkProtocolUpgradeCouncilGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @custom:security-contact security@zksync.io
/// @notice A governor through which the members of a council propose protocol upgrades. Each member holds a seat in a
/// non-transferable council token, and any member holding at least the proposal threshold can submit a proposal. A
/// proposal succeeds once its FOR votes alone meet quorum, however many members vote AGAINST or ABSTAIN, so with a
/// quorum of one seat a single member is enough to sponsor it. A successful proposal is not executed by this
/// governor: queueing it submits the same actions to a veto governor, where token holders have the chance to stop
/// them before they are executed.
/// @dev Quorum and super-quorum are fractions of the council token's supply. When both are at most one seat, the first
/// FOR vote meets them, and `state` reports `Succeeded` immediately rather than at the end of the voting period. A
/// proposal with no FOR votes is `Defeated` once its voting period ends.
contract ZkProtocolUpgradeCouncilGovernor is BasicCouncilGovernor {
  /// @param _name The name used as the EIP712 signing domain.
  /// @param _token The council token, whose seats carry the voting power.
  /// @param _councilVetoGovernor The veto governor that successful proposals are submitted to.
  /// @param _governorAdmin The address allowed to change the governor's parameters.
  /// @param _params The initial voting delay, voting period, proposal threshold, quorum and super-quorum fractions.
  constructor(
    string memory _name,
    IERC5805 _token,
    IGovernor _councilVetoGovernor,
    address _governorAdmin,
    InitialCouncilParams memory _params
  ) BasicCouncilGovernor(_name, _token, _councilVetoGovernor, _governorAdmin, _params) {}

  /// @notice Returns whether a proposal's FOR votes meet quorum. AGAINST and ABSTAIN votes are ignored, so members
  /// voting against a proposal cannot outvote its sponsor.
  /// @param _proposalId The identifier of the proposal to check.
  /// @return Whether the proposal has at least one FOR vote and its FOR votes meet quorum at the proposal snapshot.
  /// @dev Requiring at least one FOR vote keeps a proposal with no votes from succeeding if quorum is ever zero, e.g.
  /// when no seats exist at the snapshot.
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
