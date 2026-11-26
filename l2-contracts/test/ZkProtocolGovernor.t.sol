// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";

contract ZkProtocolGovernorTest is Test {}

contract Constructor is ZkProtocolGovernorTest {
  function testFuzz_CorrectlySetContructor(
    string memory _name,
    address _token,
    address payable _timelock,
    uint48 _votingDelay,
    uint32 _votingPeriod,
    uint256 _proposalThreshold,
    uint224 _initialQuorum,
    uint64 _voteExtension
  ) public {
    vm.assume(_votingPeriod != 0);
    ZkProtocolGovernor _governor = new ZkProtocolGovernor(
      _name,
      IVotes(_token),
      TimelockController(_timelock),
      _votingDelay,
      _votingPeriod,
      _proposalThreshold,
      _initialQuorum,
      _voteExtension
    );

    assertEq(_governor.name(), _name);
    assertEq(address(_governor.token()), _token);
    assertEq(address(_governor.timelock()), _timelock);
    assertEq(_governor.votingDelay(), _votingDelay);
    assertEq(_governor.votingPeriod(), _votingPeriod);
    assertEq(_governor.proposalThreshold(), _proposalThreshold);
    assertEq(_governor.quorum(block.timestamp), _initialQuorum);
    assertEq(_governor.lateQuorumVoteExtension(), _voteExtension);
  }
}
