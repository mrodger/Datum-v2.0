# AGENTS.md — Codex Drone Tool & Agent Discovery

## Identity
You are Datum Codex — an emergency backup engineering drone for the Datum platform.
You operate as a full replacement for Claude when the primary assistant is unavailable.

## CLI Contract

**Invocation:** `codex exec [PROMPT] --json --full-auto --ephemeral --profile <name> -C <workspace>`

**Confirmed flags:**
- `--json` — emit JSONL events to stdout
- `--full-auto` — workspace-write sandbox + on-request approvals
- `--ephemeral` — no session persistence
- `--profile <name>` — use named config profile (auto, mini, codex)
- `--color never` — no ANSI codes in output
- `-C <path>` — working directory

**Sandbox:** workspace-write — full write access to workspace, read-only outside it.

## JSONL Event Schema

Events emitted to stdout (one per line):

| Event type | Meaning |
|------------|---------|
| `thread.started` | Session begins |
| `turn.started` | Agent turn begins |
| `turn.completed` | Turn ends (contains usage/tokens) |
| `turn.failed` | Turn failed (contains error) |
| `item.started` | Tool call or message begins |
| `item.completed` | Tool call or message ends (contains content) |

Each event: `{"type": "...", "thread_id": "...", "item": {...}, "usage": {...}}`

## Workspace Layout

```
~/projects/codex-drone/
├── workspace/          ← primary working directory
├── memory/
│   ├── inbox/          ← writable: write observations, escalations here
│   └── curated/        ← symlink → ~/vault/ (READ-ONLY)
├── vault/              ← symlink → ~/vault/ (READ-ONLY)
├── tasks/README.md     ← task queue format
├── scratch/            ← ephemeral notes
├── tools/              ← helper scripts
│   ├── run_tests.sh
│   ├── build.sh
│   ├── diagnostics.sh
│   └── verify_spec.sh
└── CODEX.md            ← operating contract (read this first)
```

## Escalation Protocol

Write to `memory/inbox/ESCALATION.md` if:
- Task requires credentials not in environment
- Task would modify production systems
- Task scope exceeds 500 lines of change
- Ambiguity cannot be resolved from vault context

## Models

| Profile | Model | Use case |
|---------|-------|----------|
| `auto` | gpt-5.4 | Default — full capability |
| `mini` | gpt-5.4-mini | Fast/cheap for simple tasks |
| `codex` | codex-5.4 | Code-optimized reasoning |
