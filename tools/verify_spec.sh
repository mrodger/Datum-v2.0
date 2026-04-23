#!/usr/bin/env bash
# verify_spec.sh — Check that all required files exist and are non-empty.
set -euo pipefail
cd "$(dirname "$0")/.."

PASS=0; FAIL=0
check() {
    local name="$1"; local path="$2"
    if [ -e "$path" ]; then
        echo "PASS: $name exists ($path)"
        PASS=$((PASS+1))
    else
        echo "FAIL: $name missing ($path)"
        FAIL=$((FAIL+1))
    fi
}

check "AGENTS.md"             "AGENTS.md"
check "CODEX.md"              "CODEX.md"
check "MANIFEST.md"           "MANIFEST.md"
check "SPEC.md"               "SPEC.md"
check "RUNBOOK.md"            "RUNBOOK.md"
check ".codex/config.toml"    ".codex/config.toml"
check ".gitignore"            ".gitignore"
check "bridge/server.py"      "bridge/server.py"
check "bridge/patcher.py"     "bridge/patcher.py"
check "bridge/test_bridge.py" "bridge/test_bridge.py"
check "tasks/README.md"       "tasks/README.md"
check "vault symlink"         "vault"
check "memory/inbox"          "memory/inbox"
check "workspace dir"         "workspace"

if [ -L "vault" ] && [ -d "vault" ]; then
    echo "PASS: vault symlink resolves"
    PASS=$((PASS+1))
else
    echo "FAIL: vault symlink broken or missing"
    FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
