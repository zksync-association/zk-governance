#!/usr/bin/env bash
#
# verify.sh — verify all deployed governance contracts.
#   * L1 (Sepolia): re-runs the deploy script with `--resume --verify --verifier sourcify`, which
#     re-uses the existing broadcast (no new transactions) and submits sources to Sourcify (keyless).
#   * L2 (Era testnet): best-effort `hardhat verify`. This sovereign testnet exposes no public
#     contract-verification API at the time of writing, so this step may report failures; the full
#     sources, exact compiler versions and constructor arguments are recorded in deployed-addresses.md
#     so anyone can reproduce the bytecode.
#
# Reads $STATE_DIR/l1.env (written by redeploy.sh step l1). Requires PRIVATE_KEY for --resume.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
L1DIR="$REPO/l1-contracts"
L2DIR="$REPO/l2-contracts"
OUT="$HERE/deployments"
STATE_DIR="$HERE/.redeploy-state"
export L1_RPC="${L1_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
export L2_RPC="${L2_RPC:-https://rpc.zksync-era-testnet.zksync.dev/}"

echo "=== L1 verification (Sourcify) ==="
if [ -f "$STATE_DIR/l1.env" ]; then
  # shellcheck disable=SC1090
  set -a; . "$STATE_DIR/l1.env"; set +a
  ( cd "$L1DIR" && \
    PRIVATE_KEY="${PRIVATE_KEY:?set PRIVATE_KEY}" \
    forge script script/DeployL1Governance.s.sol --rpc-url "$L1_RPC" \
      --resume --verify --verifier sourcify ) || echo "[verify] L1 sourcify verification reported errors"
else
  echo "[verify] no l1.env; skipping L1"
fi

echo "=== L2 verification (best-effort) ==="
if [ -f "$OUT/l2-governance.json" ]; then
  TOKEN=$(node -e "console.log(require('$OUT/l2-governance.json').zkToken)")
  GOV=$(node -e "console.log(require('$OUT/l2-governance.json').governor)")
  TL=$(node -e "console.log(require('$OUT/l2-governance.json').timelock)")
  ( cd "$L2DIR" && npx hardhat verify --network eraTestnet "$GOV" ) \
    || echo "[verify] L2 governor verification unavailable on this testnet"
  ( cd "$L2DIR" && npx hardhat verify --network eraTestnet "$TL" ) \
    || echo "[verify] L2 timelock verification unavailable on this testnet"
  echo "[verify] L2 token is a transparent proxy at $TOKEN (verify impl/proxy via the explorer if available)"
else
  echo "[verify] no l2-governance.json; skipping L2"
fi
