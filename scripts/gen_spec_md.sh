#!/usr/bin/env bash
# Outputs SPEC.md — implementation specification
cat << 'EOF'
# SPEC.md — Codex Drone Implementation Spec

## Architecture

```
User (agentic-ui :8090 or standalone :8132)
    │
    ▼
Codex Bridge (FastAPI :8092)
    │  POST /chat  {messages, model}
    │  SSE response: text / tool_use / done / error events
    ▼
codex exec --json --full-auto --ephemeral
    │  JSONL: item.completed / turn.completed / turn.failed
    ▼
OpenAI Codex (gpt-5.4 / gpt-5.4-mini / codex-5.4)
```

## Key Ports

| Port | Service |
|------|---------|
| `:8090` | agentic-ui (Codex persona via patcher.py) |
| `:8092` | Codex bridge (FastAPI, host-only) |
| `:8132` | Standalone Codex UI (Docker container) |

## Security

- **Bridge token:** `CODEX_BRIDGE_TOKEN` shared secret (X-Authorization: Bearer)
- **Subprocess env:** Only `PATH`, `HOME`, `OPENAI_API_KEY`, `NO_COLOR` injected
- **Path allowlist:** Only `~/projects/*` permitted as workspace roots
- **Vault:** Read-only symlink; Codex sandbox enforces write restriction
- **No exposed auth:** `:8132` has no login — do not expose publicly

## Config

| Variable | Default | Purpose |
|----------|---------|---------|
| `CODEX_BRIDGE_TOKEN` | (required) | Shared auth secret |
| `CODEX_BRIDGE_PORT` | 8092 | Bridge listen port |
| `CODEX_TIMEOUT_S` | 600 | Wall-clock timeout per task |
| `CODEX_IDLE_TIMEOUT_S` | 120 | Idle timeout (no output) |
| `CODEX_DAILY_BUDGET` | 20.0 | USD daily spend cap |
| `CODEX_MAX_CONCURRENT` | 2 | Max parallel Codex processes |
| `OPENAI_API_KEY` | (required) | OpenAI authentication |

## Event Protocol

Bridge translates Codex JSONL → SSE events matching agentic-ui format:

| agentic-ui event | From Codex JSONL |
|-----------------|-----------------|
| `{type: "text", text: ...}` | `item.completed` (message content) |
| `{type: "tool_use", name: ..., input: ...}` | `item.completed` (tool_call/command) |
| `{type: "done", cost_usd: ...}` | `turn.completed` (usage) |
| `{type: "error", detail: ...}` | `turn.failed` or subprocess error |
EOF
