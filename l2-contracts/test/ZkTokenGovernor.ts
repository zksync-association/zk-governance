import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import { expect } from "chai";
import hre from "hardhat";
import type { ZkTokenGovernor } from "../typechain-types";

const accounts = [
  {
    address: "0x36615Cf349d7F6344891B1e7CA7C72883F5dc049",
    privateKey:
      "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110",
  },
];

describe("ZkTokenGovernor", function () {
  let tokenGovernor: ZkTokenGovernor;

  const name = "zkSync Token Governor";
  const mockTokenAddr = "0xCAFEcaFE00000000000000000000000000000000";
  const mockTimelockAddr = "0x55bE1B079b53962746B2e86d12f158a41DF294A6";
  const mockVetoGuardian = "0xdEADBEeF00000000000000000000000000000000";
  const mockProposeGuardian = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";
  const votingDelay = 100;
  const votingPeriod = 120;
  const proposalThreshold = 1100;
  const initialQuorum = 1200;
  const initialLateQuorum = 1300;
  const isProposeGuarded = true;

  before("Deploy Governor", async function () {
    const [deployerAccount] = accounts;
    const deployerWallet = new Wallet(deployerAccount.privateKey);
    const deployer = new Deployer(hre, deployerWallet);
    const ZkTokenGovernor = await deployer.loadArtifact("ZkTokenGovernor");
    tokenGovernor = (await deployer.deploy(ZkTokenGovernor, [
      {
        name,
        initialQuorum,
        isProposeGuarded,
        token: mockTokenAddr,
        timelock: mockTimelockAddr,
        initialVotingDelay: votingDelay,
        initialVotingPeriod: votingPeriod,
        initialProposalThreshold: proposalThreshold,
        initialVoteExtension: initialLateQuorum,
        vetoGuardian: mockVetoGuardian,
        proposeGuardian: mockProposeGuardian,
      },
    ])) as unknown as ZkTokenGovernor;
  });

  describe("Constructor", function () {
    it("Set paramters correctly", async function () {
      const block = await hre.ethers.provider.getBlock("latest");

      expect(await tokenGovernor.name()).to.equal(name);
      expect(await tokenGovernor.token()).to.equal(mockTokenAddr);
      expect(await tokenGovernor.votingDelay()).to.equal(votingDelay);
      expect(await tokenGovernor.votingPeriod()).to.equal(votingPeriod);
      expect(await tokenGovernor.quorum(block?.timestamp || 0)).to.equal(
        initialQuorum
      );
      expect(await tokenGovernor.lateQuorumVoteExtension()).to.equal(
        initialLateQuorum
      );
      expect(await tokenGovernor.timelock()).to.equal(mockTimelockAddr);
      expect(await tokenGovernor.VETO_GUARDIAN()).to.equal(mockVetoGuardian);
      expect(await tokenGovernor.PROPOSE_GUARDIAN()).to.equal(
        mockProposeGuardian
      );
      expect(await tokenGovernor.isProposeGuarded()).to.equal(isProposeGuarded);
    });
  });
});
