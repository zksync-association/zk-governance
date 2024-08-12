import { Provider } from "zksync-ethers";

const l2Provider = new Provider("https://sepolia.era.zksync.dev");

const hardcodedProposal = "([(0x0000000000000000000000000000000000000000, 0, 0x)],0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000000000000000000000000000)";
export async function getL2LogProof(hash: string, index: number) {
  console.log(`Getting L2 message proof for transaction ${hash} and index ${index}`);
  const receipt = await l2Provider.getTransactionReceipt(hash);
  const proof = await l2Provider.getLogProof(hash, index);
  console.log(`_l2BatchNumber: `, receipt.l1BatchNumber);
  console.log(`_l2MessageIndex: `, proof?.id);
  console.log(`_l2TxNumberInBatch: `, receipt.l1BatchTxIndex);
  console.log(`_proof: `, proof?.proof);
  console.log(`_proposal: `, hardcodedProposal);
  return proof;
}

try {
  // To run this script on stand alone mode, you need to provide the transaction hash and L2 tx index
  const TX_HASH = "0x7be3434dd5f886bfe2fe446bf833f09d1be08e0a644a4996776fec569c3801a0";
  const L2_TX_INDEX = 0;

  getL2LogProof(TX_HASH, L2_TX_INDEX);
} catch (error) {
  console.error(error);
}
