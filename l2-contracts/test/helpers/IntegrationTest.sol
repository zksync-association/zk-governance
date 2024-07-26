// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Constants} from "test/utils/Constants.sol";
import {ProposalTest} from "test/helpers/ProposalTest.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IGovernorTimelock} from "@openzeppelin/contracts/governance/extensions/IGovernorTimelock.sol";

interface ERC20VotesMintable is IVotes, IAccessControl {
  function mint(address _account, uint256 _amount) external;
  function MINTER_ADMIN_ROLE() external returns (bytes32);
  function BURNER_ADMIN_ROLE() external returns (bytes32);
  function MINTER_ROLE() external returns (bytes32);
  function BURNER_ROLE() external returns (bytes32);
  function DEFAULT_ADMIN_ROLE() external returns (bytes32);
  function balanceOf(address) external returns (uint256);
  function totalSupply() external returns (uint256);
}

interface IGovernorSettings {
  function proposalThreshold() external view returns (uint256);
}

contract IntegrationTest is Constants, ProposalTest {
  ERC20VotesMintable token = ERC20VotesMintable(DEPLOYED_TOKEN_ADDRESS);
  TimelockController timelock;
  IGovernorTimelock governor;
  address admin = makeAddr("Admin");

  function _createDelegates(uint16 _num) internal returns (address[] memory) {
    address[] memory delegates = new address[](_num);
    for (uint256 i = 0; i < _num; i++) {
      delegates[i] = makeAddr(vm.toString(i));
    }
    return delegates;
  }

  function _grantTimelockDefaultAdmin() internal {
    bytes32 _defaultAdminRole = token.DEFAULT_ADMIN_ROLE();
    vm.prank(TOKEN_ADMIN_ADDRESS);
    token.grantRole(_defaultAdminRole, address(timelock));
  }

  function _grantTimelockMinterAdmin() internal {
    vm.startPrank(address(timelock));
    token.grantRole(token.MINTER_ADMIN_ROLE(), address(timelock));
    vm.stopPrank();
  }

  function _grantTimelockBurnerAdmin() internal {
    vm.startPrank(address(timelock));
    token.grantRole(token.BURNER_ADMIN_ROLE(), address(timelock));
    vm.stopPrank();
  }

  function _grantTimelockMinterRole() internal {
    vm.startPrank(address(timelock));
    token.grantRole(token.MINTER_ROLE(), address(timelock));
    vm.stopPrank();
  }

  function _grantTimelockBurnerRole() internal {
    vm.startPrank(address(timelock));
    token.grantRole(token.BURNER_ROLE(), address(timelock));
    vm.stopPrank();
  }

  function _mintExistingTokens(address _delegate, uint256 _amount) internal {
    bytes32 _minterAdminRole = token.MINTER_ADMIN_ROLE();
    vm.prank(TOKEN_ADMIN_ADDRESS);
    token.grantRole(_minterAdminRole, admin);

    bytes32 _minterRole = token.MINTER_ROLE();
    vm.prank(admin);
    token.grantRole(_minterRole, admin);

    vm.prank(admin);
    token.mint(_delegate, _amount);

    vm.prank(_delegate);
    token.delegate(_delegate);
  }

  function _setGovernorAndDelegates() internal returns (address[] memory) {
    _setGovernor(governor);
    address[] memory delegates = _createDelegates(10);
    for (uint256 i = 0; i < 10; i++) {
      _mintExistingTokens(delegates[i], IGovernorSettings(address(governor)).proposalThreshold());
    }
    _setDelegates(delegates);
    vm.warp(vm.getBlockTimestamp() + 1);
    return delegates;
  }

  function _queueAndExecuteProposal(ProposalBuilder builder, string memory _description) internal {
    uint256 _proposalId = governor.propose(builder.targets(), builder.values(), builder.calldatas(), _description);
    vm.stopPrank();
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, 1);
    _jumpPastVoteComplete(_proposalId);

    governor.queue(builder.targets(), builder.values(), builder.calldatas(), keccak256(bytes(_description)));

    _jumpPastProposalEta(_proposalId);
    governor.execute(builder.targets(), builder.values(), builder.calldatas(), keccak256(bytes(_description)));
  }
}
