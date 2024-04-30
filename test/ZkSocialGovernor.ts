import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import { Wallet } from "zksync-ethers";
import { expect } from "chai";
import hre from "hardhat";
import type { ZkSocialGovernor } from "../typechain-types";

const accounts = [
  {
    address: "0x36615Cf349d7F6344891B1e7CA7C72883F5dc049",
    privateKey:
      "0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110",
  },
];

describe("ZkSocialGovernor", function () {
  let socialGovernor: ZkSocialGovernor;

  const name = "zkSync Social Governor";
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

    const ZkSocialGovernor = await deployer.loadArtifact(
      "ZkSocialGovernor"
    );
    socialGovernor = (await deployer.deploy(ZkSocialGovernor, [
      name,
      mockTokenAddr,
      mockTimelockAddr,
      votingDelay,
      votingPeriod,
      proposalThreshold,
      initialQuorum,
      initialLateQuorum,
			mockGuardian
    ])) as unknown as ZkSocialGovernor;
  });

  describe("Constructor", function () {
    it("Set paramters correctly", async function () {
      const block = await hre.ethers.provider.getBlock("latest");

      expect(await socialGovernor.name()).to.equal(name);
      expect(await socialGovernor.token()).to.equal(mockTokenAddr);
      expect(await socialGovernor.votingDelay()).to.equal(votingDelay);
      expect(await socialGovernor.votingPeriod()).to.equal(votingPeriod);
      expect(await socialGovernor.proposalThreshold()).to.equal(
        proposalThreshold
      );
      expect(await socialGovernor.quorum(block?.timestamp || 0)).to.equal(
        initialQuorum
      );
      expect(await socialGovernor.lateQuorumVoteExtension()).to.equal(
        initialLateQuorum
      );
      expect(await socialGovernor.timelock()).to.equal(mockTimelockAddr);
      expect(await socialGovernor.GUARDIAN()).to.equal(mockGuardian);
    });
  });
});
