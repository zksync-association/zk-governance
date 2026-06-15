/**
 * Fast, single-confirmation transaction confirmation for the ZKsync Era testnet used here.
 *
 * This chain does NOT mine empty blocks, so ethers' `.wait()` / `waitForDeployment()` (which wait
 * for a *subsequent* confirmation block) hang for as long as the chain is idle. We only need the
 * tx's own inclusion (1 confirmation), so we poll `eth_getTransactionReceipt(hash)` directly — the
 * receipt appears ~1-3s after sending. As a fallback (in case a locally-computed hash ever differs
 * from the mined one) we also detect inclusion via the sender's nonce and locate the tx by scanning
 * the few most-recent blocks.
 */
import { Provider } from "zksync-ethers";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export interface ConfirmedReceipt {
  transactionHash: string;
  contractAddress?: string;
  blockNumber: number;
  status: number;
  logs: any[];
}

function normalize(r: any, fallbackBlock?: number): ConfirmedReceipt {
  const status = r && r.status !== undefined ? Number(r.status) : 1;
  return {
    transactionHash: r.transactionHash,
    contractAddress: r.contractAddress ?? undefined,
    blockNumber: Number(r.blockNumber ?? fallbackBlock ?? 0),
    status,
    logs: r.logs ?? [],
  };
}

export async function confirmTx(
  provider: Provider,
  hash: string,
  from: string,
  nonce: number,
  label = "tx",
  timeoutSec = 180
): Promise<ConfirmedReceipt> {
  const sender = from.toLowerCase();
  const deadline = Date.now() + timeoutSec * 1000;
  let lastScanned = Number.MAX_SAFE_INTEGER;
  if (process.env.ZKWAIT_DEBUG) console.error(`[confirm ${label}] hash=${hash} from=${sender} nonce=${nonce}`);
  let iter = 0;

  while (Date.now() < deadline) {
    iter++;
    // Fast path: receipt by the tx hash (works as soon as the tx is included, ~1-3s).
    try {
      const r: any = await provider.send("eth_getTransactionReceipt", [hash]);
      if (r) {
        if (Number(r.status) === 0) throw new Error(`${label} reverted (${hash})`);
        return normalize(r);
      }
    } catch (e: any) {
      if (String(e.message || "").includes("reverted")) throw e;
    }

    // Fallback: inclusion detected via nonce; find the tx in the most recent blocks.
    const cnt = await provider.getTransactionCount(sender, "latest");
    if (process.env.ZKWAIT_DEBUG && iter % 4 === 1) console.error(`[confirm ${label}] iter=${iter} txcount=${cnt}`);
    if (cnt > nonce) {
      const latest = await provider.getBlockNumber();
      const floor = Math.max(0, Math.min(lastScanned, latest) - 6);
      for (let b = latest; b >= floor; b--) {
        let blk: any;
        try {
          blk = await provider.send("eth_getBlockByNumber", ["0x" + b.toString(16), true]);
        } catch {
          continue;
        }
        for (const tx of blk?.transactions || []) {
          if (typeof tx === "string") continue;
          if ((tx.from || "").toLowerCase() === sender && Number(tx.nonce) === nonce) {
            const r: any = await provider.send("eth_getTransactionReceipt", [tx.hash]);
            if (r && Number(r.status) === 0) throw new Error(`${label} reverted (${tx.hash})`);
            return normalize(r ?? { transactionHash: tx.hash }, b);
          }
        }
      }
      lastScanned = latest;
    }
    await sleep(500);
  }
  throw new Error(`${label}: not confirmed within ${timeoutSec}s (hash ${hash}, nonce ${nonce})`);
}

/** Confirm a just-sent ethers/zksync TransactionResponse via its hash (fast) + (from,nonce) fallback. */
export async function confirmResponse(provider: Provider, resp: any, label = "tx"): Promise<ConfirmedReceipt> {
  return confirmTx(provider, resp.hash, resp.from, Number(resp.nonce), label);
}
