#!/usr/bin/env bash
#
# redeploy.sh — one-shot, resumable redeployment of the FULL ZKsync governance stack.
#
# Given a single deployer private key it:
#   1. funds the deployer on L2 by bridging ETH from L1 (Sepolia)                  [step: bridge]
#   2. deploys the L2 ZK token (V2 proxy), TimelockController and ZkProtocolGovernor,
#      minting the initial supermajority ZK supply to the deployer/user            [step: l2]
#   3. deploys the L1 governance (TestnetProtocolUpgradeHandler behind a proxy,
#      SecurityCouncil, Guardians, EmergencyUpgradeBoard + 21 member Safes),
#      wired to the L2 timelock                                                      [step: l1]
#   4. assembles governance.json (cli-tool config) + deployed-addresses.md         [step: assemble]
#   5. verifies all deployed contracts (Sourcify on L1, zksync verifier on L2)     [step: verify]
#
# Each step writes a marker under $STATE_DIR; completed steps are skipped on re-run, so the
# script can be stopped (e.g. while waiting for the L2 deposit) and resumed later.
#
# Required env:
#   PRIVATE_KEY   deployer/user key (holds Sepolia ETH; receives the minted ZK)
# Optional env (sane Sepolia / Era-testnet defaults):
#   L1_RPC L2_RPC SAFE_OWNER BRIDGE_AMOUNT ZK_MINT_AMOUNT
#
# Usage:  PRIVATE_KEY=0x... ./redeploy.sh [bridge|l2|l1|assemble|verify|all]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
L1DIR="$REPO/l1-contracts"
L2DIR="$REPO/l2-contracts"
OUT="$HERE/deployments"
STATE_DIR="$HERE/.redeploy-state"
mkdir -p "$OUT" "$STATE_DIR"

: "${PRIVATE_KEY:?set PRIVATE_KEY}"
export L1_RPC="${L1_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
export L2_RPC="${L2_RPC:-https://rpc.zksync-era-testnet.zksync.dev/}"
export SAFE_OWNER="${SAFE_OWNER:-0xD64e136566a9E04eb05B30184fF577F52682D182}"
export BRIDGE_AMOUNT="${BRIDGE_AMOUNT:-0.025}"
export ZK_MINT_AMOUNT="${ZK_MINT_AMOUNT:-10000000000}"

TS="$HERE/node_modules/.bin/ts-node --project $HERE/tsconfig.json"
done_marker() { [ -f "$STATE_DIR/$1.done" ]; }
mark_done() { touch "$STATE_DIR/$1.done"; }

step_bridge() {
  if done_marker bridge; then echo "[bridge] already done"; return; fi
  echo "[bridge] funding L2 deployer ..."
  ( cd "$HERE" && PRIVATE_KEY="$PRIVATE_KEY" $TS bridge-to-l2.ts )
  mark_done bridge
}

step_l2() {
  if done_marker l2; then echo "[l2] already done"; return; fi
  echo "[l2] deploying L2 governance ..."
  ( cd "$HERE" && \
    DEPLOYER_PRIVATE_KEY="$PRIVATE_KEY" L2_RPC="$L2_RPC" L2_OUT="$OUT/l2-governance.json" \
    ZK_MINT_AMOUNT="$ZK_MINT_AMOUNT" $TS deploy-l2.ts )
  mark_done l2
}

step_l1() {
  if done_marker l1; then echo "[l1] already done"; return; fi
  echo "[l1] deploying L1 governance ..."
  local timelock saltbase
  timelock=$(node -e "console.log(require('$OUT/l2-governance.json').timelock)")
  saltbase="$(date +%s)000"
  echo "[l1] L2_PROTOCOL_GOVERNOR (timelock) = $timelock"
  # Persist inputs so `verify` can deterministically resume/reproduce the same addresses.
  cat > "$STATE_DIR/l1.env" <<EOF
L2_PROTOCOL_GOVERNOR=$timelock
SALT_BASE=$saltbase
SAFE_OWNER=$SAFE_OWNER
L1_OUT=$OUT/l1-governance.json
EOF
  ( cd "$L1DIR" && \
    PRIVATE_KEY="$PRIVATE_KEY" L2_PROTOCOL_GOVERNOR="$timelock" \
    SALT_BASE="$saltbase" L1_OUT="$OUT/l1-governance.json" SAFE_OWNER="$SAFE_OWNER" \
    forge script script/DeployL1Governance.s.sol --rpc-url "$L1_RPC" --broadcast --slow )
  mark_done l1
}

step_assemble() {
  echo "[assemble] writing governance.json + deployed-addresses.md ..."
  ( cd "$HERE" && SAFE_OWNER="$SAFE_OWNER" $TS lib/assemble.ts \
    "$OUT/l2-governance.json" "$OUT/l1-governance.json" "$HERE/governance.json" "$HERE/deployed-addresses.md" )
  mark_done assemble
}

step_verify() {
  echo "[verify] verifying contracts (best-effort) ..."
  ( cd "$HERE" && bash verify.sh ) || echo "[verify] some verifications failed (see log)"
  mark_done verify
}

cmd="${1:-all}"
case "$cmd" in
  bridge) step_bridge ;;
  l2) step_l2 ;;
  l1) step_l1 ;;
  assemble) step_assemble ;;
  verify) step_verify ;;
  all)
    step_bridge
    step_l2
    step_l1
    step_assemble
    step_verify
    echo "=== redeploy complete ==="
    cat "$HERE/deployed-addresses.md"
    ;;
  *) echo "unknown step: $cmd"; exit 1 ;;
esac
