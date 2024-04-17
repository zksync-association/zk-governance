import { Wallet, Contract } from "zksync-ethers";
import { Deployer } from "@matterlabs/hardhat-zksync-deploy";
import * as hre from "hardhat";
import { Addressable } from "ethers";
import { computeAddress } from "@ethersproject/transactions";
import ZkTokenV1 from "../artifacts-zk/src/ZkTokenV1.sol/ZkTokenV1.json";

// This is the expected address of the token contract when deployed locally via the zkSync local node
const LOCALLY_DEPLOYED_TOKEN_ADDRESS = "0x99E12239CBf8112fBB3f7Fd473d0558031abcbb5";

export async function getTokenContract(tokenAddress: string | Addressable): Promise<Contract> {
  const tokenScriptExecutorPrivateKey = process.env.TOKEN_SCRIPT_EXECUTOR_PRIVATE_KEY;
  if (!tokenScriptExecutorPrivateKey) {
    throw "Please set TOKEN_SCRIPT_EXECUTOR_PRIVATE_KEY in your .env file";
  }
  const zkWallet = new Wallet(tokenScriptExecutorPrivateKey);
  const deployer = new Deployer(hre, zkWallet);
  const tokenContract = await new Contract(tokenAddress, ZkTokenV1.abi, deployer.zkWallet);
  return tokenContract;
}

async function privateKeyIsHardhatSigner(privateKey: string): Promise<boolean> {
  const signers = await hre.ethers.getSigners();
  for (const signer of signers) {
    if ((await signer.getAddress()) === computeAddress(privateKey)) {
      return true;
    }
  }
  return false;
}

