// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorPreventLateQuorum} from "@openzeppelin/contracts/governance/extensions/GovernorPreventLateQuorum.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/Checkpoints.sol";
import {GovernorCountingFractional} from "src/lib/GovernorCountingFractional.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title ZkProtocolGovernor
/// @author [ScopeLift](https://scopelift.co)
/// @notice A Governance contract used to manage protocol upgrades.
contract ZkProtocolGovernor is
  GovernorCountingFractional,
  GovernorSettings,
  GovernorVotes,
  GovernorTimelockControl,
  GovernorPreventLateQuorum
{
  using Checkpoints for Checkpoints.Trace224;

  /// @notice A history of quorum values for a given timestamp.
  Checkpoints.Trace224 internal _quorumCheckpoints;

  /// @param _name The name used as the EIP712 signing domain.
  /// @param _token The token used for voting on proposals.
  /// @param _timelock The timelock used for managing proposals.
  /// @param _initialVotingDelay The delay before voting on a proposal begins.
  /// @param _initialVotingPeriod The period of time voting will take place.
  /// @param _initialProposalThreshold The number of tokens needed to create a proposal.
  /// @param _initialQuorum The number of total votes needed to pass a proposal.
  /// @param _initialVoteExtension The time to extend the voting period if quorum is met near the end of voting.
  constructor(
    string memory _name,
    IVotes _token,
    TimelockController _timelock,
    uint48 _initialVotingDelay,
    uint32 _initialVotingPeriod,
    uint256 _initialProposalThreshold,
    uint224 _initialQuorum,
    uint64 _initialVoteExtension
  )
    Governor(_name)
    GovernorSettings(_initialVotingDelay, _initialVotingPeriod, _initialProposalThreshold)
    GovernorVotes(_token)
    GovernorTimelockControl(_timelock)
    GovernorPreventLateQuorum(_initialVoteExtension)
  {
    _setQuorum(_initialQuorum);
  }

  /// @inheritdoc GovernorCountingFractional
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function castVoteWithReasonAndParamsBySig(
    uint256 _proposalId,
    uint8 _support,
    string calldata _reason,
    bytes memory _params,
    uint8 _v,
    bytes32 _r,
    bytes32 _s
  ) public override(Governor, GovernorCountingFractional, IGovernor) returns (uint256) {
    return
      GovernorCountingFractional.castVoteWithReasonAndParamsBySig(_proposalId, _support, _reason, _params, _v, _r, _s);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalDeadline(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, IGovernor, GovernorPreventLateQuorum)
    returns (uint256)
  {
    return GovernorPreventLateQuorum.proposalDeadline(_proposalId);
  }

  /// @inheritdoc GovernorSettings
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function proposalThreshold() public view virtual override(Governor, GovernorSettings) returns (uint256) {
    return GovernorSettings.proposalThreshold();
  }

  /// @notice A function to get the quorum threshold for a given timestamp.
  /// @param _voteStart The timestamp of when voting starts for a given proposal.
  function quorum(uint256 _voteStart) public view override returns (uint256) {
    return _quorumCheckpoints.upperLookup(SafeCast.toUint32(_voteStart));
  }
  /// @notice A function to set quorum for the current block timestamp. Proposals created after this timestamp will be
  /// subject to the new quorum.
  /// @param _amount The new quorum threshold.

  function setQuorum(uint224 _amount) external onlyGovernance {
    _setQuorum(_amount);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function state(uint256 _proposalId)
    public
    view
    virtual
    override(Governor, GovernorTimelockControl)
    returns (IGovernor.ProposalState)
  {
    return GovernorTimelockControl.state(_proposalId);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(Governor, GovernorTimelockControl)
    returns (bool)
  {
    return GovernorTimelockControl.supportsInterface(_interfaceId);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _cancel(
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockControl) returns (uint256) {
    return GovernorTimelockControl._cancel(_targets, _values, _calldatas, _descriptionHash);
  }

  /// @inheritdoc GovernorPreventLateQuorum
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _castVote(uint256 _proposalId, address _account, uint8 _support, string memory _reason, bytes memory _params)
    internal
    virtual
    override(Governor, GovernorPreventLateQuorum)
    returns (uint256)
  {
    return GovernorPreventLateQuorum._castVote(_proposalId, _account, _support, _reason, _params);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _execute(
    uint256 _proposalId,
    address[] memory _targets,
    uint256[] memory _values,
    bytes[] memory _calldatas,
    bytes32 _descriptionHash
  ) internal virtual override(Governor, GovernorTimelockControl) {
    return GovernorTimelockControl._execute(_proposalId, _targets, _values, _calldatas, _descriptionHash);
  }

  /// @inheritdoc GovernorTimelockControl
  /// @dev We override this function to resolve ambiguity between inherited contracts.
  function _executor() internal view virtual override(Governor, GovernorTimelockControl) returns (address) {
    return GovernorTimelockControl._executor();
  }

  /// @notice A function to set quorum for the current block timestamp.
  /// @param _amount The quorum amount to checkpoint.
  function _setQuorum(uint224 _amount) internal {
    _quorumCheckpoints.push(SafeCast.toUint32(block.timestamp), _amount);
  }
}
