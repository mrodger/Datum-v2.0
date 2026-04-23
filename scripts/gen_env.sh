#!/usr/bin/env bash
# Outputs .env for codex-drone project root.
# Only writes OPENAI_API_KEY and CODEX_BIN — CODEX_BRIDGE_TOKEN is injected
# by bootstrap.sh from agentic-ui .env after this script runs.
set -euo pipefail

OPENAI_KEY=$(grep -m1 '^OPENAI_API_KEY=' ~/.secrets.env | cut -d= -f2-)
if [ -z "$OPENAI_KEY" ]; then
    echo "# WARNING: OPENAI_API_KEY not found in ~/.secrets.env — set manually" >&2
    echo "OPENAI_API_KEY="
else
    echo "OPENAI_API_KEY=$OPENAI_KEY"
fi

echo "CODEX_BIN=codex"
echo "CODEX_BRIDGE_PORT=8092"
echo "CODEX_TIMEOUT_S=600"
echo "CODEX_IDLE_TIMEOUT_S=120"
echo "CODEX_DAILY_BUDGET=20.0"
echo "CODEX_MAX_CONCURRENT=2"
