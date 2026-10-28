// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {CouncilERC20} from "council-governance/CouncilERC20.sol";
import {ZkProtocolUpgradeCouncilGovernor} from "src/ZkProtocolUpgradeCouncilGovernor.sol";
import {ZkProtocolUpgradeVetoGovernor} from "src/ZkProtocolUpgradeVetoGovernor.sol";
import {ZkProtocolUpgradeEraMainnetConfig} from "script/configs/ZkProtocolUpgradeEraMainnetConfig.sol";
import {FakeSupermajorityGovernor} from "test/fakes/FakeSupermajorityGovernor.sol";
import {
  DeployZkProtocolUpgradeGovernanceEraMainnetHarness
} from "test/harnesses/DeployZkProtocolUpgradeGovernanceHarness.sol";

interface IZkCheatcodes {
  function zkVmSkip() external;
}

// EraVM's system contract that stores each deployed contract's code hash.
interface IAccountCodeStorage {
  function getRawCodeHash(address _address) external view returns (bytes32);
}

/// @notice Runs the Era mainnet council deployment on a fork of Era mainnet, against the live ZK token and Protocol
/// Timelock. Only the Supermajority Governor and override timelock, which are not deployed yet, are test doubles.
/// @dev The script is deployed behind `zkVmSkip`, so under `--zksync` it lands in the EVM, where its cheatcodes work,
/// as `forge script --zksync` runs it.
contract DeployZkProtocolUpgradeGovernanceTest is Test, ZkProtocolUpgradeEraMainnetConfig {
  string constant ZKSYNC_RPC_URL = "https://mainnet.era.zksync.io";
  // A fork block where the ZK token and the Protocol Timelock are both deployed.
  uint256 constant FORK_BLOCK = 72_650_000;
  IAccountCodeStorage constant ACCOUNT_CODE_STORAGE = IAccountCodeStorage(0x0000000000000000000000000000000000008002);

  function setUp() public virtual {
    vm.createSelectFork(ZKSYNC_RPC_URL, FORK_BLOCK);
    // The default sender pays for the EraVM transactions the script broadcasts.
    vm.deal(DEFAULT_SENDER, 1 ether);
  }

  // Deploys a test double of the override timelock as `DeploySupermajorityGovernor` leaves it: anyone executes and the
  // timelock administers itself. The real one is an OpenZeppelin v4 contract this project cannot build. The test
  // contract keeps OpenZeppelin v5's admin role, so tests can grant extra roles; it is not the deployer the checks look
  // at.
  function _deployOverrideTimelock(DeploymentParams memory _params) internal returns (TimelockController _timelock) {
    address[] memory _openExecutor = new address[](1);
    _timelock = new TimelockController(_params.overrideTimelockMinDelay, new address[](0), _openExecutor, address(this));
    _timelock.grantRole(TIMELOCK_ADMIN_ROLE, address(_timelock));
  }

  // Deploys a test double of the Supermajority Governor with `_settings`, as the override timelock's proposer and
  // canceller.
  function _deployGovernor(TimelockController _timelock, FakeSupermajorityGovernor.Settings memory _settings)
    internal
    returns (address)
  {
    FakeSupermajorityGovernor _governor = new FakeSupermajorityGovernor(_settings);
    _timelock.grantRole(_timelock.PROPOSER_ROLE(), address(_governor));
    _timelock.grantRole(_timelock.CANCELLER_ROLE(), address(_governor));
    return address(_governor);
  }

  // Deploys the Supermajority Governor and override timelock as `DeploySupermajorityGovernor` leaves them.
  function _deploySupermajorityGovernor(DeploymentParams memory _params)
    internal
    returns (address _governor, TimelockController _timelock)
  {
    _timelock = _deployOverrideTimelock(_params);
    _governor = _deployGovernor(_timelock, _supermajorityGovernorSettings(_params, address(_timelock)));
  }

  // The settings `DeploySupermajorityGovernor` gives the Supermajority Governor, from the same params the council
  // deployment checks it against.
  function _supermajorityGovernorSettings(DeploymentParams memory _params, address _timelock)
    internal
    pure
    returns (FakeSupermajorityGovernor.Settings memory)
  {
    return FakeSupermajorityGovernor.Settings({
      name: _params.supermajorityGovernorName,
      token: _params.zkToken,
      timelock: _timelock,
      votingDelay: _params.supermajorityGovernorVotingDelay,
      votingPeriod: _params.supermajorityGovernorVotingPeriod,
      proposalThreshold: _params.supermajorityGovernorProposalThreshold,
      quorum: _params.supermajorityGovernorQuorum,
      lateQuorumVoteExtension: _params.supermajorityGovernorLateQuorumVoteExtension
    });
  }

  // Deploys the script in the EVM rather than EraVM, as `forge script --zksync` runs it. Under `--zksync` a plain `new`
  // would deploy the script to EraVM, which has no cheatcodes.
  function _deployScript(
    DeploymentParams memory _params,
    address _supermajorityGovernor,
    TimelockController _overrideTimelock,
    address _supermajorityGovernorDeployer
  ) internal returns (DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script) {
    IZkCheatcodes(address(vm)).zkVmSkip();
    _script = new DeployZkProtocolUpgradeGovernanceEraMainnetHarness(
      _params, _supermajorityGovernor, _overrideTimelock, _supermajorityGovernorDeployer
    );
    _script.disableLogging();
  }

  function _deployScript(
    DeploymentParams memory _params,
    address _supermajorityGovernor,
    TimelockController _overrideTimelock
  ) internal returns (DeployZkProtocolUpgradeGovernanceEraMainnetHarness) {
    return _deployScript(_params, _supermajorityGovernor, _overrideTimelock, address(0));
  }

  // Deploys the Supermajority Governor and override timelock with the mainnet params, then deploys and runs the script.
  function _runScript() internal returns (DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script) {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    _script = _deployScript(_params, _governor, _timelock);
    _script.run();
  }

  // The roles the deployer must not hold on the override timelock: OpenZeppelin v4's admin role, which the real
  // override timelock uses, v5's, which a wrong timelock might, and the proposer, canceller and executor roles.
  function _boundToTimelockRole(TimelockController _timelock, uint256 _roleIndex) internal view returns (bytes32) {
    bytes32[5] memory _roles = [
      TIMELOCK_ADMIN_ROLE, bytes32(0), _timelock.PROPOSER_ROLE(), _timelock.CANCELLER_ROLE(), _timelock.EXECUTOR_ROLE()
    ];
    return _roles[_bound(_roleIndex, 0, 4)];
  }
}

contract Run is DeployZkProtocolUpgradeGovernanceTest {
  function test_MintsOneSeatToEachCouncilMemberAndHandsTheTokenToTheGovernanceAdmin() public {
    CouncilERC20 _councilToken = _runScript().councilToken();

    assertEq(_councilToken.name(), "ZKsync Protocol Upgrade Council Seat");
    assertEq(_councilToken.symbol(), "ZKPUC");
    assertEq(_councilToken.owner(), GOVERNANCE_ADMIN);
    assertEq(_councilToken.totalSupply(), 8e18);
    address[] memory _councilMembers = _deploymentParams().councilMembers;
    for (uint256 _i = 0; _i < _councilMembers.length; _i += 1) {
      assertEq(_councilToken.getVotes(_councilMembers[_i]), 1e18);
    }
  }

  function test_DeploysTheCouncilGovernorWiredToTheVetoGovernor() public {
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _runScript();
    ZkProtocolUpgradeCouncilGovernor _councilGovernor = _script.councilGovernor();

    assertEq(_councilGovernor.name(), "ZKsync Protocol Upgrade Council");
    assertEq(address(_councilGovernor.token()), address(_script.councilToken()));
    assertEq(_councilGovernor.QUORUM(), 1e18);
    assertEq(address(_councilGovernor.councilVetoGovernor()), address(_script.vetoGovernor()));
    assertEq(_councilGovernor.owner(), GOVERNANCE_ADMIN);
    assertEq(_councilGovernor.votingDelay(), 1 days);
    assertEq(_councilGovernor.votingPeriod(), 3 days);
    assertEq(_councilGovernor.proposalThreshold(), 1e18);
  }

  function test_DeploysTheVetoGovernorWithTheZipParameters() public {
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _runScript();
    ZkProtocolUpgradeVetoGovernor _vetoGovernor = _script.vetoGovernor();

    assertEq(_vetoGovernor.name(), "ZKsync Protocol Upgrade Veto Governor");
    assertEq(address(_vetoGovernor.token()), ZK_TOKEN);
    assertEq(_vetoGovernor.COUNCIL(), address(_script.councilGovernor()));
    assertEq(_vetoGovernor.timelock(), PROTOCOL_TIMELOCK);
    assertEq(_vetoGovernor.owner(), GOVERNANCE_ADMIN);
    assertEq(_vetoGovernor.votingDelay(), 1 days);
    assertEq(_vetoGovernor.votingPeriod(), 7 days);
    assertEq(_vetoGovernor.vetoThreshold(block.timestamp), 630_000_000e18);
    assertEq(_vetoGovernor.votingPeriodExtension(), 2 days);
    assertEq(_vetoGovernor.minorVetoExtensionThresholdPct(), 50);
    assertEq(_vetoGovernor.vetoGuardian(), 0xF197677d63BF6E2841F5108b8dFd2FD6eCEff74B);
    assertEq(_vetoGovernor.vetoOverrideRole(), address(_script.overrideTimelock()));
    assertEq(_vetoGovernor.vetoOverrideDuration(), 14 days);
  }

  function test_LeavesTheDeployerNoSeatOrAdminRole() public {
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _runScript();

    assertEq(_script.councilToken().balanceOf(DEFAULT_SENDER), 0);
    assertTrue(_script.councilToken().owner() != DEFAULT_SENDER);
    assertTrue(_script.councilGovernor().owner() != DEFAULT_SENDER);
    assertTrue(_script.vetoGovernor().owner() != DEFAULT_SENDER);
  }

  // Only contracts deployed to EraVM have a code hash in `ACCOUNT_CODE_STORAGE`, so this fails if the script, which
  // runs in the EVM, deploys its contracts there too.
  function test_DeploysTheContractsToEraVm() public {
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _runScript();

    assertNotEq(ACCOUNT_CODE_STORAGE.getRawCodeHash(address(_script.councilToken())), bytes32(0));
    assertNotEq(ACCOUNT_CODE_STORAGE.getRawCodeHash(address(_script.councilGovernor())), bytes32(0));
    assertNotEq(ACCOUNT_CODE_STORAGE.getRawCodeHash(address(_script.vetoGovernor())), bytes32(0));
  }

  function test_DeploysWhenTheSupermajorityGovernorHasADifferentDeployer() public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script =
      _deployScript(_params, _governor, _timelock, makeAddr("Supermajority Governor Deployer"));

    _script.run();

    assertEq(_script.vetoGovernor().vetoOverrideRole(), address(_timelock));
  }

  function testFuzz_RevertIf_TheOverrideTimelockDoesNotBelongToTheSupermajorityGovernor(address _otherTimelock) public {
    DeploymentParams memory _params = _deploymentParams();
    TimelockController _timelock = _deployOverrideTimelock(_params);
    vm.assume(_otherTimelock != address(_timelock));
    address _governor = _deployGovernor(_timelock, _supermajorityGovernorSettings(_params, _otherTimelock));
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert("SupermajorityGovernorChecks: the Supermajority Governor's timelock is not the override timelock");
    _script.run();
  }

  function testFuzz_RevertIf_TheSupermajorityGovernorHasADifferentQuorum(uint256 _quorum) public {
    DeploymentParams memory _params = _deploymentParams();
    vm.assume(_quorum != _params.supermajorityGovernorQuorum);
    TimelockController _timelock = _deployOverrideTimelock(_params);
    FakeSupermajorityGovernor.Settings memory _settings = _supermajorityGovernorSettings(_params, address(_timelock));
    _settings.quorum = _quorum;
    address _governor = _deployGovernor(_timelock, _settings);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert("SupermajorityGovernorChecks: Supermajority Governor quorum does not match the params");
    _script.run();
  }

  function testFuzz_RevertIf_TheVetoOverrideWindowIsShorterThanASupermajorityOverride(uint256 _duration) public {
    DeploymentParams memory _params = _deploymentParams();
    // The window must be strictly longer than a supermajority override, so its length is already too short.
    uint256 _longestOverride = uint256(_params.supermajorityGovernorVotingDelay)
      + _params.supermajorityGovernorVotingPeriod + _params.supermajorityGovernorLateQuorumVoteExtension
      + _params.overrideTimelockMinDelay;
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    _params.vetoGovernorVetoOverrideDuration = uint48(_bound(_duration, 0, _longestOverride));
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert(
      "SupermajorityGovernorChecks: vetoGovernorVetoOverrideDuration is too short for a supermajority override"
    );
    _script.run();
  }

  function test_RevertIf_TheVetoGuardianIsTheZeroAddress() public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    _params.vetoGovernorVetoGuardian = address(0);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert(
      "DeployZkProtocolUpgradeGovernance: vetoGovernorVetoGuardian is the zero address; set the veto guardian"
    );
    _script.run();
  }

  function test_RevertIf_TheProtocolTimelockHasNoCode() public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    _params.protocolTimelock = makeAddr("Account Without Code");
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert("DeployZkProtocolUpgradeGovernance: protocolTimelock has no code; set it to the Protocol Timelock");
    _script.run();
  }

  function testFuzz_RevertIf_TheDeployerHoldsARoleOnTheOverrideTimelock(uint256 _roleIndex) public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    _timelock.grantRole(_boundToTimelockRole(_timelock, _roleIndex), DEFAULT_SENDER);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script = _deployScript(_params, _governor, _timelock);

    vm.expectRevert("SupermajorityGovernorChecks: the deployer holds a role on the override timelock");
    _script.run();
  }

  function test_RevertIf_TheSupermajorityGovernorDeployerHoldsARoleOnTheOverrideTimelock() public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    address _supermajorityGovernorDeployer = makeAddr("Supermajority Governor Deployer");
    _timelock.grantRole(_timelock.PROPOSER_ROLE(), _supermajorityGovernorDeployer);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script =
      _deployScript(_params, _governor, _timelock, _supermajorityGovernorDeployer);

    vm.expectRevert("SupermajorityGovernorChecks: the deployer holds a role on the override timelock");
    _script.run();
  }
}

contract Check is DeployZkProtocolUpgradeGovernanceTest {
  function test_PassesForTheDeploymentRunMade() public {
    DeploymentParams memory _params = _deploymentParams();
    (address _governor, TimelockController _timelock) = _deploySupermajorityGovernor(_params);
    DeployZkProtocolUpgradeGovernanceEraMainnetHarness _script =
      _deployScript(_params, _governor, _timelock, makeAddr("Supermajority Governor Deployer"));
    _script.run();
    vm.setEnv("SUPERMAJORITY_GOVERNOR", vm.toString(_governor));
    vm.setEnv("OVERRIDE_TIMELOCK", vm.toString(address(_timelock)));
    vm.setEnv("COUNCIL_TOKEN", vm.toString(address(_script.councilToken())));
    vm.setEnv("COUNCIL_GOVERNOR", vm.toString(address(_script.councilGovernor())));
    vm.setEnv("VETO_GOVERNOR", vm.toString(address(_script.vetoGovernor())));
    vm.setEnv("DEPLOYER", vm.toString(DEFAULT_SENDER));

    _script.check();
  }
}
