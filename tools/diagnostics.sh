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
