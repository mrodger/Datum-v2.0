#!/usr/bin/env bash
# gen_tools.sh — Write all tools/*.sh helper scripts.
# Called by bootstrap.sh (no arguments). Creates files directly.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")/tools"
mkdir -p "$TOOLS_DIR"

# ── tools/verify_spec.sh ─────────────────────────────────────────────────────
cat > "$TOOLS_DIR/verify_spec.sh" << 'INNEREOF'
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
INNEREOF

# ── tools/diagnostics.sh ─────────────────────────────────────────────────────
cat > "$TOOLS_DIR/diagnostics.sh" << 'INNEREOF'
#!/usr/bin/env bash
# diagnostics.sh — System readiness check.
set -uo pipefail
cd "$(dirname "$0")/.."

echo "=== Codex Drone Diagnostics ==="
echo "Date: $(date)"
echo ""
echo "--- Runtime ---"
echo "Node:    $(node --version 2>/dev/null || echo NOT_FOUND)"
echo "npm:     $(npm --version 2>/dev/null || echo NOT_FOUND)"
echo "codex:   $(codex --version 2>/dev/null || echo NOT_FOUND)"
echo "python3: $(python3 --version 2>/dev/null || echo NOT_FOUND)"
echo "docker:  $(docker --version 2>/dev/null || echo NOT_FOUND)"
echo ""
echo "--- Environment ---"
echo "OPENAI_API_KEY:     $([ -n "${OPENAI_API_KEY:-}" ] && echo SET || echo NOT_SET)"
echo "CODEX_BRIDGE_TOKEN: $([ -n "${CODEX_BRIDGE_TOKEN:-}" ] && echo SET || echo NOT_SET)"
echo ""
echo "--- Mounts ---"
if [ -L "vault" ] && [ -d "vault" ]; then
    echo "vault symlink: OK -> $(readlink vault)"
else
    echo "vault symlink: BROKEN"
fi
if [ -L "memory/curated" ] && [ -d "memory/curated" ]; then
    echo "memory/curated: OK"
else
    echo "memory/curated: BROKEN"
fi
echo ""
echo "--- Bridge deps ---"
python3 -c "import fastapi; print('fastapi:', fastapi.__version__)" 2>/dev/null || echo "fastapi: NOT INSTALLED"
python3 -c "import uvicorn; print('uvicorn:', uvicorn.__version__)" 2>/dev/null || echo "uvicorn: NOT INSTALLED"
python3 -c "import httpx; print('httpx:', httpx.__version__)" 2>/dev/null || echo "httpx: NOT INSTALLED"
python3 -c "import dotenv; print('python-dotenv: OK')" 2>/dev/null || echo "python-dotenv: NOT INSTALLED"
echo ""
echo "--- Bridge status ---"
if curl -s --max-time 3 http://localhost:8092/health 2>/dev/null | python3 -m json.tool 2>/dev/null; then
    echo "Bridge: RUNNING"
else
    echo "Bridge: NOT RUNNING (start with: python3 bridge/server.py)"
fi
INNEREOF

# ── tools/run_tests.sh ───────────────────────────────────────────────────────
cat > "$TOOLS_DIR/run_tests.sh" << 'INNEREOF'
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
INNEREOF

# ── tools/build.sh ───────────────────────────────────────────────────────────
cat > "$TOOLS_DIR/build.sh" << 'INNEREOF'
#!/usr/bin/env bash
# build.sh — Build or rebuild the standalone Codex UI container.
set -euo pipefail
UI_DIR="$(dirname "$0")/../ui"

if [ ! -d "$UI_DIR" ]; then
    echo "Standalone UI not provisioned. Run bootstrap.sh first."
    exit 1
fi

cd "$UI_DIR"
echo "Building codex-ui container..."
docker compose build
echo "Done. Start with: docker compose up -d"
INNEREOF

chmod +x "$TOOLS_DIR/verify_spec.sh" "$TOOLS_DIR/diagnostics.sh" "$TOOLS_DIR/run_tests.sh" "$TOOLS_DIR/build.sh"
echo "gen_tools.sh: tools/ scripts written"
