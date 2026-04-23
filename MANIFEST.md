# MANIFEST.md — Codex Drone Module

## Purpose
Codex Drone is an emergency backup engineering agent for the Datum platform. It provides
full software engineering capabilities (coding, analysis, file manipulation, git operations)
via OpenAI Codex when the primary Claude-based assistant is unavailable.

It does NOT replace Datum's security, credential management, or orchestration layers.
It does NOT have write access to the vault or production systems.

## Dependencies

| Dependency | Purpose | Failure behaviour |
|------------|---------|-------------------|
| `@openai/codex` CLI | Shell + file tools for the agent | Bridge returns 503 |
| `OPENAI_API_KEY` env | Authentication to OpenAI | Bridge refuses to start |
| Codex Bridge `:8092` | Translates chat → codex exec | UI shows error event |
| `~/vault/` symlink | Read-only project context | Agent operates without context |
| `agentic-ui` `:8090` | Primary user interface | Use standalone UI `:8132` |

## Dependents

| Caller | Contract |
|--------|----------|
| `agentic-ui server.py` | Calls `run_codex_agent(messages, model)` async generator |
| Standalone UI `:8132` | Calls bridge `/chat` via `agent.py` proxy |
| Bridge `/chat` endpoint | Runs `codex exec --json --full-auto --ephemeral` subprocess |

## Failure Modes

| Mode | Symptom | Recovery |
|------|---------|---------|
| Codex CLI missing | Bridge `/health` → `codex_binary: false` | `npm i -g @openai/codex` |
| No API key | Bridge `/health` → `api_key_set: false` | Source `~/.secrets.env` |
| Budget exhausted | Bridge returns 429 | Wait or raise `CODEX_DAILY_BUDGET` |
| Task timeout | Stream ends with error event | Raise `CODEX_TIMEOUT_S` |
| Bridge down | UI shows "bridge unreachable" | `cd ~/projects/codex-drone && python3 bridge/server.py` |

## Behavioral Contracts

- **Side effects:** Each invocation runs `codex exec` as a subprocess. May write files under `~/projects/`.
- **State:** Stateless bridge — no session persistence between calls (`--ephemeral` flag).
- **Retry semantics:** No automatic retry. Client must re-send on error.
- **Cost tracking:** Daily spend tracked in-memory; resets at midnight UTC.
- **Concurrency:** Max 2 parallel Codex processes (configurable via `CODEX_MAX_CONCURRENT`).
