/**
 * Shared helpers for building the ZKsync protocol-upgrade proposal that travels L2 -> L1.
 *
 * The flow encoded here mirrors `ProtocolUpgradeHandler.startUpgrade`:
 *   - An `UpgradeProposal { Call[] calls; address executor; bytes32 salt }` describes the L1
 *     actions to perform.
 *   - Its ABI encoding is the bytes payload of an L2->L1 message sent via the L2 `L1Messenger`
 *     system contract (0x..8008) `sendToL1(bytes)`.
 *   - On L1 the handler recomputes `keccak256(abi.encode(proposal))` as the upgrade id and
 *     verifies the message was sent by `L2_PROTOCOL_GOVERNOR` (the L2 timelock that executes the
 *     governor's queued calls).
 *
 * Therefore the L2 governor proposal we build contains a single call:
 *   target  = L2_MESSENGER
 *   data    = sendToL1(abi.encode(upgradeProposal))
 */
import { ethers } from "ethers";

export const L2_MESSENGER = "0x0000000000000000000000000000000000008008";

// Tuple type matching IProtocolUpgradeHandler.UpgradeProposal (calls, executor, salt).
export const UPGRADE_PROPOSAL_TYPE =
  "tuple(tuple(address target,uint256 value,bytes data)[] calls,address executor,bytes32 salt)";

export const L1_MESSENGER_ABI = ["function sendToL1(bytes _message) returns (bytes32)"];

export interface Call {
  target: string;
  value: bigint | string | number;
  data: string;
}

export interface UpgradeProposal {
  calls: Call[];
  executor: string;
  salt: string;
}

/** Normalize a loosely-typed JSON spec into a strict UpgradeProposal. */
export function normalizeProposal(spec: any): UpgradeProposal {
  if (!spec || !Array.isArray(spec.calls) || spec.calls.length === 0) {
    throw new Error("Proposal spec must contain a non-empty `calls` array");
  }
  const calls: Call[] = spec.calls.map((c: any, i: number) => {
    if (!ethers.isAddress(c.target)) throw new Error(`calls[${i}].target is not an address`);
    return {
      target: ethers.getAddress(c.target),
      value: c.value !== undefined ? BigInt(c.value) : 0n,
      data: c.data && c.data !== "" ? ethers.hexlify(c.data) : "0x",
    };
  });
  const executor = spec.executor ? ethers.getAddress(spec.executor) : ethers.ZeroAddress;
  const salt = spec.salt ? ethers.zeroPadValue(ethers.hexlify(spec.salt), 32) : ethers.ZeroHash;
  return { calls, executor, salt };
}

/** ABI-encode the UpgradeProposal exactly as `abi.encode(proposal)` does in Solidity. */
export function encodeUpgradeProposal(p: UpgradeProposal): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    [UPGRADE_PROPOSAL_TYPE],
    [[p.calls.map((c) => [c.target, BigInt(c.value), c.data]), p.executor, p.salt]]
  );
}

/** The upgrade id used on L1 == keccak256(abi.encode(proposal)). */
export function upgradeId(p: UpgradeProposal): string {
  return ethers.keccak256(encodeUpgradeProposal(p));
}

/** Calldata for L1Messenger.sendToL1(message). */
export function sendToL1Calldata(message: string): string {
  const iface = new ethers.Interface(L1_MESSENGER_ABI);
  return iface.encodeFunctionData("sendToL1", [message]);
}

/**
 * Build the L2 governor proposal arguments (targets/values/calldatas) that, when executed,
 * emit the L2->L1 upgrade message.
 */
export function buildGovernorProposal(p: UpgradeProposal): {
  targets: string[];
  values: bigint[];
  calldatas: string[];
  message: string;
  id: string;
} {
  const message = encodeUpgradeProposal(p);
  return {
    targets: [L2_MESSENGER],
    values: [0n],
    calldatas: [sendToL1Calldata(message)],
    message,
    id: ethers.keccak256(message),
  };
}
