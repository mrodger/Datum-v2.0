#!/usr/bin/env bash
# run_tests.sh — Run all tests for the codex-drone workspace.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "=== Codex Drone Test Suite ==="
FAIL=0

echo ""
echo "--- Bridge unit tests (offline) ---"
python3 bridge/test_bridge.py --offline || FAIL=$((FAIL+1))

echo ""
echo "--- Spec verification ---"
bash tools/verify_spec.sh || FAIL=$((FAIL+1))

echo ""
echo "=== FAIL count: $FAIL ==="
[ "$FAIL" -eq 0 ]
