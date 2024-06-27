// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {console2} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProposalBuilder} from "test/helpers/ProposalBuilder.sol";
import {IntegrationTest} from "test/helpers/IntegrationTest.sol";

import {ZkProtocolGovernor} from "src/ZkProtocolGovernor.sol";
import {ZkTokenUpgradeFake} from "test/fakes/ZkTokenUpgradeFake.sol";

contract ZkProtocolGovernorIntegrationBase is IntegrationTest {
  function setUp() public virtual {
    // Create a fork of the ZKSync ERA mainnet, at a point in time after the ZK token was deployed
    vm.createSelectFork(vm.rpcUrl(ZKSYNC_RPC_URL), 36_326_417);

    // Deploy the timelock, initially with this test script as its admin (will change later)
    timelock = new TimelockController(0, new address[](0), new address[](0), address(this));

    // Deploy the token governor
    governor = new ZkProtocolGovernor(
      "Example Protocol Governor",
      IVotes(address(token)),
      timelock,
      INITIAL_VOTING_DELAY,
      INITIAL_VOTING_PERIOD,
      INITIAL_PROPOSAL_THRESHOLD,
      INITIAL_QUORUM,
      INITIAL_VOTE_EXTENSION
    );

    // Grant the necessary roles to the governor
    timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
    timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
    timelock.grantRole(timelock.EXECUTOR_ROLE(), address(governor));
  }
}

contract ZKProtocolTokenUpgradeTest is ZkProtocolGovernorIntegrationBase {
  /// @dev Represents a call to be made during an upgrade.
  /// @dev Original source:
  /// https://github.com/matter-labs/zk-governance/blob/main/l1-contracts/src/interfaces/IProtocolUpgradeHandler.sol
  /// @param target The address to which the call will be made.
  /// @param value The amount of Ether (in wei) to be sent along with the call.
  /// @param data The calldata to be executed on the `target` address.
  struct Call {
    address target;
    uint256 value;
    bytes data;
  }

  /// @dev Defines the structure of an upgrade that is executed by Protocol Upgrade Handler.
  /// @dev Original source:
  /// https://github.com/matter-labs/zk-governance/blob/main/l1-contracts/src/interfaces/IProtocolUpgradeHandler.sol
  /// @param executor The L1 address that is authorized to perform the upgrade execution (if address(0) then anyone).
  /// @param calls An array of `Call` structs, each representing a call to be made during the upgrade execution.
  /// @param salt A bytes32 value used for creating unique upgrade proposal hashes.
  struct UpgradeProposal {
    Call[] calls;
    address executor;
    bytes32 salt;
  }

  event L1MessageSent(address indexed _sender, bytes32 indexed _hash, bytes _message);

  function _emptyProposal(bytes32 _salt) internal pure returns (UpgradeProposal memory) {
    return UpgradeProposal({calls: new Call[](0), executor: address(0), salt: _salt});
  }

  function _buildEmptyUpgradeCalldata() internal pure returns (bytes memory) {
    UpgradeProposal memory proposal = _emptyProposal("1");
    return (
      abi.encodeWithSignature(
        "startUpgrade(uint256,uint256,uint16,bytes32[],address,bytes32[])",
        0,
        0,
        0,
        new bytes32[](0),
        proposal.executor,
        proposal.salt
      )
    );
  }

  function testFork_ProtocolUpgrade() public {
    _setGovernorAndDelegates();

    // create a token upgrade proposal
    ProposalBuilder _builder = new ProposalBuilder();
    bytes memory emptyUpgradeCalldata = _buildEmptyUpgradeCalldata();
    bytes memory sendToL1call = abi.encodeWithSignature("sendToL1(bytes)", emptyUpgradeCalldata);
    _builder.push(L1_MESSENGER_ADDRESS, 0, sendToL1call);

    vm.startPrank(delegates[0]);
    uint256 _proposalId =
      governor.propose(_builder.targets(), _builder.values(), _builder.calldatas(), UPGRADE_DESCRIPTION);
    vm.stopPrank();
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, 1);
    _jumpPastVoteComplete(_proposalId);

    governor.queue(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(UPGRADE_DESCRIPTION)));

    _jumpPastProposalEta(_proposalId);

    vm.expectEmit(address(L1_MESSENGER_ADDRESS));
    emit L1MessageSent(address(timelock), keccak256(emptyUpgradeCalldata), emptyUpgradeCalldata);

    governor.execute(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(UPGRADE_DESCRIPTION)));
  }

  // Upgrade the token
  function testFork_TokenUpgrade() public {
    _setGovernorAndDelegates();
    ZkTokenUpgradeFake newTokenImpl = new ZkTokenUpgradeFake();

    vm.prank(TOKEN_PROXY_ADMIN);
    ITransparentUpgradeableProxy(DEPLOYED_TOKEN_ADDRESS).changeAdmin(address(timelock));

    // create a token upgrade proposal
    ProposalBuilder _builder = new ProposalBuilder();
    bytes memory tokenUpgradeCall = abi.encodeWithSignature(
      "upgradeToAndCall(address,bytes)", address(newTokenImpl), abi.encodeCall(ZkTokenUpgradeFake.initializeFake, ())
    );
    _builder.push(DEPLOYED_TOKEN_ADDRESS, 0, tokenUpgradeCall);

    vm.startPrank(delegates[0]);
    uint256 _proposalId =
      governor.propose(_builder.targets(), _builder.values(), _builder.calldatas(), UPGRADE_DESCRIPTION);
    vm.stopPrank();
    _jumpToActiveProposal(_proposalId);

    _delegatesVote(_proposalId, 1);
    _jumpPastVoteComplete(_proposalId);

    governor.queue(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(UPGRADE_DESCRIPTION)));

    _jumpPastProposalEta(_proposalId);

    governor.execute(_builder.targets(), _builder.values(), _builder.calldatas(), keccak256(bytes(UPGRADE_DESCRIPTION)));

    assertEq(ZkTokenUpgradeFake(DEPLOYED_TOKEN_ADDRESS).name(), "ZKsyncFake");
  }
}
