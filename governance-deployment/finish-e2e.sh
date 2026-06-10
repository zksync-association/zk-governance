#!/usr/bin/env bash
# Helper used during the cli-vote end-to-end test: wait until a proposal's voting deadline has
# really elapsed (this chain's block.timestamp only advances on activity), then queue + execute it
# and print the emitted L2->L1 message. Args: <proposalId> <deadlineEpoch>
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
PID="$1"; DEADLINE="$2"
TS="node_modules/.bin/ts-node --project tsconfig.json"
echo "waiting for deadline $DEADLINE (now $(date +%s)) ..."
while [ "$(date +%s)" -le "$((DEADLINE + 10))" ]; do sleep 10; done
echo "deadline passed (now $(date +%s))"
echo "=== queue ==="
$TS cli-vote.ts queue --proposal "$PID"
echo "=== execute ==="
$TS cli-vote.ts execute --proposal "$PID"
echo "=== message ==="
$TS cli-vote.ts message --proposal "$PID"
