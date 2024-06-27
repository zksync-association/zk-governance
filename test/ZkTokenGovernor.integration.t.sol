// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {console2} from "forge-std/Test.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";

import {ZkTokenGovernor} from "src/ZkTokenGovernor.sol";
import {IntegrationTest} from "test/helpers/IntegrationTest.sol";

contract ZkTokenGovernorIntegrationBase is IntegrationTest {
  address vetoGuardian = makeAddr("Veto guardian");
  address proposeGuardian = makeAddr("Propose guardian");

  function setUp() public virtual {
    vm.createSelectFork(vm.rpcUrl(ZKSYNC_RPC_URL), 36_326_417);

    // Deploy the timelock
    timelock = new TimelockController(0, new address[](0), new address[](0), admin);

    // Deploy the token governor
    ZkTokenGovernor.ConstructorParams memory params = ZkTokenGovernor.ConstructorParams({
      name: "Example Gov",
      token: IVotes(DEPLOYED_TOKEN_ADDRESS),
      timelock: timelock,
      initialVotingDelay: INITIAL_VOTING_DELAY,
      initialVotingPeriod: INITIAL_VOTING_PERIOD,
      initialProposalThreshold: INITIAL_PROPOSAL_THRESHOLD,
      initialQuorum: INITIAL_QUORUM,
      initialVoteExtension: INITIAL_VOTE_EXTENSION,
      vetoGuardian: vetoGuardian,
      proposeGuardian: proposeGuardian,
      isProposeGuarded: false
    });
    governor = new ZkTokenGovernor(params);
    console2.logAddress(address(governor));

    vm.prank(admin);
    timelock.grantRole(keccak256("PROPOSER_ROLE"), address(governor));

    vm.prank(admin);
    timelock.grantRole(keccak256("EXECUTOR_ROLE"), address(governor));

    vm.prank(admin);
    timelock.grantRole(keccak256("CANCELLER_ROLE"), address(governor));

    vm.prank(admin);
    timelock.revokeRole(keccak256("TIMELOCK_ADMIN_ROLE"), admin);
  }
}

contract ZkTokenGovernorTest is ZkTokenGovernorIntegrationBase {
  function testForkFuzz_AssignMinterAdminRoleToAnAddress(address _minterAdmin, string memory _description) public {
    _grantTimelockDefaultAdmin();
    _setGovernorAndDelegates();

    ProposalBuilder builder = new ProposalBuilder();
    builder.push(
      DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ADMIN_ROLE, _minterAdmin)
    );

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);

    assertTrue(token.hasRole(MINTER_ADMIN_ROLE, _minterAdmin));
  }

  function testForkFuzz_AssignMinterRoleToAnAddress(address _minter, string memory _description) public {
    _grantTimelockDefaultAdmin();
    _grantTimelockMinterAdmin();

    _setGovernorAndDelegates();
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("grantRole(bytes32,address)", MINTER_ROLE, _minter));

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);
    assertTrue(token.hasRole(MINTER_ROLE, _minter));
  }

  function testForkFuzz_AssignBurnerAdminRoleToAnAddress(address _burner, string memory _description) public {
    _grantTimelockDefaultAdmin();

    _setGovernorAndDelegates();
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(
      DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("grantRole(bytes32,address)", BURNER_ADMIN_ROLE, _burner)
    );

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);
    assertTrue(token.hasRole(BURNER_ADMIN_ROLE, _burner));
  }

  function testForkFuzz_AssignBurnerRoleToAnAddress(address _burner, string memory _description) public {
    _grantTimelockDefaultAdmin();
    _grantTimelockBurnerAdmin();

    _setGovernorAndDelegates();
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("grantRole(bytes32,address)", BURNER_ROLE, _burner));

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);

    assertTrue(token.hasRole(BURNER_ROLE, _burner));
  }

  function testForkFuzz_timlockCanMintNewTokens(address _mintee, uint256 _amount, string memory _description) public {
    vm.assume(_mintee != address(0));
    _amount = bound(_amount, 1, 1_000_000_000_000e18);
    _grantTimelockDefaultAdmin();
    _grantTimelockMinterAdmin();
    _grantTimelockMinterRole();

    _setGovernorAndDelegates();
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("mint(address,uint256)", _mintee, _amount));

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);

    assertEq(token.balanceOf(_mintee), _amount);
  }

  function testForkFuzz_timlockCanBurnTokens(
    address _tokenHolder,
    uint256 _mintAmount,
    uint256 _burnAmount,
    string memory _description
  ) public {
    vm.assume(_tokenHolder != address(0));
    _mintAmount = bound(_mintAmount, 1, 1_000_000_000_000e18);
    _burnAmount = bound(_burnAmount, 1, _mintAmount);
    _grantTimelockDefaultAdmin();
    _grantTimelockMinterAdmin();
    _grantTimelockBurnerAdmin();
    _grantTimelockMinterRole();
    _grantTimelockBurnerRole();

    vm.prank(address(timelock));
    token.mint(_tokenHolder, _mintAmount);

    _setGovernorAndDelegates();
    ProposalBuilder builder = new ProposalBuilder();
    builder.push(DEPLOYED_TOKEN_ADDRESS, 0, abi.encodeWithSignature("burn(address,uint256)", _tokenHolder, _burnAmount));

    vm.startPrank(proposeGuardian);
    _queueAndExecuteProposal(builder, _description);

    assertEq(token.balanceOf(_tokenHolder), _mintAmount - _burnAmount);
  }
}
