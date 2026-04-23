#!/usr/bin/env bash
# Outputs RUNBOOK.md — operator guide
cat << 'EOF'
# Codex Drone — Operator Runbook

## Quick Start
    source ~/.secrets.env
    cd ~/projects/codex-drone/bridge
    python server.py                     # starts on :8092

## Health Check
    curl -s localhost:8092/health | jq .
    # Returns: ready/not_ready + checks for binary, key, vault, tasks

## Switch to Codex
    1. Open agentic-ui at :8090
    2. Select "Codex" persona from sidebar
    3. Choose model: gpt-5.4 (default), gpt-5.4-mini, or codex-5.4
    4. Send message

## Switch Back to Claude
    Select any other persona. Codex conversations are separate.

## Logs
    Bridge logs to stdout in JSON format.
    Run with: python server.py 2>&1 | tee /tmp/codex-bridge.log

## Troubleshooting
    | Symptom | Cause | Fix |
    |---------|-------|-----|
    | 401 from bridge | Wrong/missing CODEX_BRIDGE_TOKEN | Check .env |
    | 503 from health | Codex binary missing or no API key | Run diagnostics.sh |
    | 429 from chat | Daily budget exceeded | Wait or raise CODEX_DAILY_BUDGET |
    | Timeout | Task too complex for 10min | Raise CODEX_TIMEOUT_S |
    | No persona in UI | Patcher didn't run | python bridge/patcher.py |

## Stop
    Kill the bridge process (Ctrl-C or kill PID).
    Active Codex subprocesses are killed automatically (process group).

## Full Re-provision
    bash bootstrap.sh     # idempotent, safe to re-run

## Standalone UI (Docker on :8132)

### Start
    cd ~/projects/codex-drone/ui
    docker compose up -d

### Stop
    cd ~/projects/codex-drone/ui
    docker compose down

### Logs
    docker logs codex-ui -f

### Rebuild after changes
    cd ~/projects/codex-drone/ui
    docker compose up -d --build

### Health check
    python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8132/').status)"

### Model selection
    Default: GPT-5.4 (set via DEFAULT_MODEL env in docker-compose.yml)
    Available: gpt-5.4, gpt-5.4-mini, codex-5.4, gpt-4o, gpt-4o-mini
    Note: All models route through the Codex bridge — no direct LLM API calls from this container

### Prerequisite
    The Codex bridge (Part C) must be running on :8092 for this UI to work.
    Start bridge first: cd ~/projects/codex-drone && python3 bridge/server.py

    IMPORTANT: Bridge must bind to 0.0.0.0:8092 (not 127.0.0.1) so Docker containers
    can reach it via host.docker.internal. Bridge is protected by CODEX_BRIDGE_TOKEN.

### Security notes
    - :8132 has no login/auth — do NOT expose publicly without upstream access control
    - Bridge token is shared between agentic-ui and standalone UI (single secret)
    - .env contains OPENAI_API_KEY — ensure it is gitignored and never in Docker image

### Data
    Conversations stored in Docker volume: codex-ui_data
    To backup: docker cp codex-ui:/app/data/codex.db ./codex-backup.db
EOF
