import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import { expect } from "chai";
import hre from "hardhat";
import type { ZkGovOpsGovernor } from "../typechain-types";

const accounts = [
  {
    address: "0x36615Cf349d7F6344891B1e7CA7C72883F5dc049",
    privateKey:
      "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110",
  },
];

describe("ZkGovOpsGovernor", function () {
  let govOpsGovernor: ZkGovOpsGovernor;

  const name = "zkSync GovOps Governor";
  const mockTokenAddr = "0xCAFEcaFE00000000000000000000000000000000";
  const mockTimelockAddr = "0x55bE1B079b53962746B2e86d12f158a41DF294A6";
  const mockGuardian = "0xdEADBEeF00000000000000000000000000000000";
  const votingDelay = 100;
  const votingPeriod = 120;
  const proposalThreshold = 1100;
  const initialQuorum = 1200;
  const initialLateQuorum = 1300;

  before("Deploy Governor", async function () {
    const [deployerAccount] = accounts;
    const deployerWallet = new Wallet(deployerAccount.privateKey);
    const deployer = new Deployer(hre, deployerWallet);

    const ZkGovOpsGovernor = await deployer.loadArtifact("ZkGovOpsGovernor");
    govOpsGovernor = (await deployer.deploy(ZkGovOpsGovernor, [
      {
        name,
        token: mockTokenAddr,
        timelock: mockTimelockAddr,
        initialVotingDelay: votingDelay,
        initialVotingPeriod: votingPeriod,
        initialProposalThreshold: proposalThreshold,
        initialQuorum: initialQuorum,
        initialVoteExtension: initialLateQuorum,
        vetoGuardian: mockGuardian,
      },
    ])) as unknown as ZkGovOpsGovernor;
  });

  describe("Constructor", function () {
    it("Set paramters correctly", async function () {
      const block = await hre.ethers.provider.getBlock("latest");

      expect(await govOpsGovernor.name()).to.equal(name);
      expect(await govOpsGovernor.token()).to.equal(mockTokenAddr);
      expect(await govOpsGovernor.votingDelay()).to.equal(votingDelay);
      expect(await govOpsGovernor.votingPeriod()).to.equal(votingPeriod);
      expect(await govOpsGovernor.proposalThreshold()).to.equal(
        proposalThreshold
      );
      expect(await govOpsGovernor.quorum(block?.timestamp || 0)).to.equal(
        initialQuorum
      );
      expect(await govOpsGovernor.lateQuorumVoteExtension()).to.equal(
        initialLateQuorum
      );
      expect(await govOpsGovernor.timelock()).to.equal(mockTimelockAddr);
      expect(await govOpsGovernor.VETO_GUARDIAN()).to.equal(mockGuardian);
    });
  });
});
