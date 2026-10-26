// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {
  GovernorVotesQuorumFraction
} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {BasicCouncilGovernor} from "council-governance/BasicCouncilGovernor.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";

/// @title ZkProtocolUpgradeCouncilGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @custom:security-contact security@zksync.io
/// @notice A governor through which the members of a council propose protocol upgrades. Each member holds a seat in a
/// non-transferable council token, and any member holding at least the proposal threshold can submit a proposal. A
/// proposal succeeds as soon as it has one seat's worth of FOR votes, however many members vote AGAINST or ABSTAIN and
/// however many seats the council has, so a single member is enough to sponsor it. A successful proposal is not
/// executed by this governor: queueing it submits the same actions to a veto governor, where token holders have the
/// chance to stop them before they are executed.
/// @dev Quorum and super-quorum are both fixed at one seat, the council token's `MAX_TOKENS_PER_MEMBER`, rather than a
/// fraction of the seat supply. The fraction settings inherited from `GovernorVotesQuorumFraction` and
/// `GovernorVotesSuperQuorumFraction` are unused: the constructor requires both fractions to be zero,
/// `updateQuorumNumerator` and `updateSuperQuorumNumerator` revert, and `quorumNumerator` and `superQuorumNumerator`
/// always return zero. Read `quorum` and `superQuorum` for the votes a proposal needs.
contract ZkProtocolUpgradeCouncilGovernor is BasicCouncilGovernor {
  /// @notice The votes one council seat carries: the most council tokens a member can hold.
  uint256 public immutable VOTES_PER_SEAT;

  /// @notice Thrown when a quorum or super-quorum fraction is configured, at construction or through its setter.
  error ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled();

  /// @param _name The name used as the EIP712 signing domain.
  /// @param _councilToken The council token, whose seats carry the voting power.
  /// @param _councilVetoGovernor The veto governor that successful proposals are submitted to.
  /// @param _governorAdmin The address allowed to change the governor's parameters.
  /// @param _params The initial voting delay, voting period and proposal threshold. The quorum and super-quorum
  /// fractions must be zero, since quorum is fixed at one seat.
  constructor(
    string memory _name,
    CouncilERC20 _councilToken,
    IGovernor _councilVetoGovernor,
    address _governorAdmin,
    InitialCouncilParams memory _params
  ) BasicCouncilGovernor(_name, IERC5805(address(_councilToken)), _councilVetoGovernor, _governorAdmin, _params) {
    if (_params.initialQuorumFraction != 0 || _params.initialSuperQuorumFraction != 0) {
      revert ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled();
    }
    VOTES_PER_SEAT = _councilToken.MAX_TOKENS_PER_MEMBER();
  }

  /// @notice Describes how votes are counted: FOR, AGAINST and ABSTAIN votes are cast as in Governor Bravo, and only
  /// FOR votes count toward quorum.
  function COUNTING_MODE() public pure virtual override(IGovernor, GovernorCountingSimple) returns (string memory) {
    return "support=bravo&quorum=for";
  }

  /// @notice Returns the votes a proposal needs to succeed, which is one seat at every timepoint.
  /// @return The votes of one seat.
  function quorum(uint256) public view virtual override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
    return VOTES_PER_SEAT;
  }

  /// @notice Returns the votes at which a proposal succeeds before its voting period ends, which is one seat at every
  /// timepoint.
  /// @return The votes of one seat.
  function superQuorum(uint256) public view virtual override returns (uint256) {
    return VOTES_PER_SEAT;
  }

  /// @notice Always reverts. Quorum is fixed at one seat.
  function updateQuorumNumerator(uint256) external virtual override {
    revert ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled();
  }

  /// @notice Always reverts. Super-quorum is fixed at one seat.
  function updateSuperQuorumNumerator(uint256) public virtual override {
    revert ZkProtocolUpgradeCouncilGovernor_QuorumFractionDisabled();
  }

  /// @notice Returns whether a proposal's FOR votes meet quorum. ABSTAIN votes do not count toward it.
  /// @param _proposalId The identifier of the proposal to check.
  /// @return Whether the proposal has at least one seat's worth of FOR votes.
  function _quorumReached(uint256 _proposalId)
    internal
    view
    virtual
    override(Governor, GovernorCountingSimple)
    returns (bool)
  {
    (, uint256 _forVotes,) = proposalVotes(_proposalId);
    return _forVotes >= quorum(proposalSnapshot(_proposalId));
  }

  /// @notice Returns true for every proposal: AGAINST votes cannot defeat a proposal, so whether it succeeds depends
  /// only on its FOR votes reaching quorum.
  /// @return Always true.
  function _voteSucceeded(uint256) internal view virtual override(Governor, GovernorCountingSimple) returns (bool) {
    return true;
  }
}
