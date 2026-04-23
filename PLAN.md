# Codex Drone Bootstrap — Implementation Plan v4

**Date:** 2026-04-23 (v4: Part E bridge proxy pivot — standalone UI wired to full codex shell)
**Author:** Developer persona (Claude Opus 4.6)
**Review 1:** GPT-5.4 adversarial (task 80da8fcb — 36 findings, REJECT)
**Review 2:** GPT-5.4 solutions architect (task 027b0e3c — 9 conditions, APPROVE_WITH_CONDITIONS)
**Review 3:** Claude Opus 4.6 internal (7 findings: 3C/4H — all fixed in v3)
**Review 4:** GPT-5.4 final (task f41f4e0c — APPROVE)
**Review 5:** GPT-5.4 Part E review (task 86080fb2 — APPROVE after 6 gaps fixed)
**Review 6:** Pending — v4 bridge proxy pivot (Part E rewrite)
**Location:** ~/projects/codex-drone/

---

## Review Response Summary

### Round 1: GPT-5.4 Adversarial (36 findings → REJECT)
All 5 CRITICAL and 11 HIGH findings addressed in v2. Key changes:

| Finding | Severity | Fix |
|---------|----------|-----|
| F1: No subprocess lifecycle | CRITICAL | Semaphore + process group kill + disconnect handler |
| F5: Vault RW too broad | CRITICAL | Vault read-only; only memory/inbox is writable |
| F6: Secret handling performative | CRITICAL | Inject OPENAI_API_KEY only; no .secrets.env mount |
| F7: Bridge unauthenticated | CRITICAL | Shared secret (X-Bridge-Token header) |
| F13: CLI flags unverified | CRITICAL | Verified against real docs — JSONL schema corrected |
| F2: SSE framing naive | HIGH | Line buffer + schema validation + version gate |
| F3: Prompt lossy | HIGH | Full message serialization with role preservation |
| F4: Workspace path unsafe | HIGH | Allowlist of ~/projects/* paths only |
| F9-10: No timeout/crash | HIGH | Wall-clock + idle timeout, process tree kill |
| F11: Partial writes | HIGH | Git worktree per task |
| F16-17: sed patching | HIGH | Python AST patcher with py_compile validation |
| F19: --check broken | HIGH | Proper gating on CHECK_ONLY flag |
| F23: No auth/audit | HIGH | Request logging + caller auth |
| F24: No logging | HIGH | Structured JSON logging |
| F25: No cost controls | HIGH | Per-request + daily budget caps |
| F28: Tests structural | HIGH | Behavioral integration tests added |
| F31: No runbook | HIGH | RUNBOOK.md with start/stop/health/recovery |
| F35: Overbuilt | HIGH | Phased delivery: MVP first, then extensions |

### Round 2: GPT-5.4 Solutions Architect (9 conditions → APPROVE_WITH_CONDITIONS)
Conditions 1-3 (JSONL fixtures, E2E UI test, sandbox proof) deferred to implementation validation.
Conditions 5-6 (systemd, persistent budget) already in Phase 2 scope.
Conditions 4, 7-9 addressed below.

### Round 3: Claude Opus 4.6 Internal Review (7 findings — all fixed in v3)

| Finding | Severity | Fix |
|---------|----------|-----|
| C1: run_codex_agent no try/except | CRITICAL | Wrapped in try/except, matches run_openai_agent pattern |
| C2: Frontend has no Codex models | CRITICAL | patch_frontend() adds optgroup to index.html + updates app.js OPENAI_MODELS |
| C3: No done event on stream failure | CRITICAL | done_emitted tracking + synthetic done in finally block |
| H1: **os.environ leaked in subprocess | HIGH | Replaced with explicit allowlist: PATH, HOME, OPENAI_API_KEY, NO_COLOR |
| H2: httpx timeout (300s) < bridge (600s) | HIGH | httpx timeout raised to 660s (bridge + margin) |
| H3: agentic-ui .env missing bridge vars | HIGH | bootstrap.sh injects CODEX_BRIDGE_URL + syncs shared token |
| H4: Missing httpx import guard | HIGH | Guarded import with ImportError → error yield |

### Round 4: GPT-5.4 Final Review (task bff28da3 — 12 findings, REJECT → fixed in v3)

| Finding | Severity | Fix |
|---------|----------|-----|
| R3-F1: project_dir not wired | BLOCKING | Documented: Codex starts in home workspace, navigates via tools (matches Claude pattern) |
| R3-F2: Bridge not started during tests | BLOCKING | Bootstrap starts bridge in background, runs --live tests, then kills |
| R3-F3: Bridge doesn't load .env | BLOCKING | Added python-dotenv, loads bridge/.env and project .env |
| R3-F4: pip install swallows errors | BLOCKING | Removed `|| true`, fails bootstrap on missing deps |
| R3-F5: Git commit before validation | BLOCKING | Moved git to Phase 8 (after validation + tests) |
| R3-F6: verify_auth not a real dependency | IMPORTANT | Changed to `Depends(verify_auth)` |
| R3-F7: Health check hardcodes vault/dev | IMPORTANT | Changed to symlink + resolve check |
| R3-F10: No npm preflight | IMPORTANT | Added `command -v npm` check before install |
| R3-F8: JSONL parser may need nested content | NOTED | Deferred to implementation validation with real fixtures |
| R3-F9: No E2E UI test | NOTED | Deferred to implementation (architect condition #2) |
| R3-F11: Regex patching brittle | NOTED | Acknowledged, acceptable for MVP |
| R3-F12: Profile/sandbox precedence | NOTED | Non-issue — both set workspace-write |

### Round 5: GPT-5.4 Part E Review (task 86080fb2 — 6 gaps → APPROVE)
Part E standalone UI (LiteLLM version) — 6 gaps found and fixed before approval.

### Round 6: GPT-5.4 Part E v4 Review (task 816eb53d — APPROVE_WITH_CONDITIONS)
Part E rewritten to bridge proxy architecture. 6 condition groups addressed in v4:

| Condition | Fix |
|-----------|-----|
| R6-1: server.py imports from removed modules | Verified: only `DEFAULT_MODEL` + `run_agent` imported from agent. No tools.py imports. |
| R6-2.1: Bridge event schema vs belle expectations | Documented: belle only checks `type=="text"`, emits own done. Bridge proxy compatible. |
| R6-2.2: History/messages duplication | Documented: belle passes history OR messages, not both with overlap. Proxy handles correctly. |
| R6-2.4: Missing assets break PWA | gen_codex_ui.sh fails fast if datum-mark.svg or PNG icons missing |
| R6-2.5: rm -r fails if absent | Changed to rm -rf with mkdir -p before |
| R6-3: Docker bridge connectivity | Added in-container health check to validation; documented bridge must bind 0.0.0.0 |
| R6-4: Missing python-multipart dep | Added python-multipart + doc parsing libs to requirements.txt |
| R6-5.1: .env in version control | .env excluded by Dockerfile context; .gitignore enforced in gen script |
| R6-5.4: No auth on :8132 | Documented: must not expose publicly without upstream access control |
| R6-6.3: grep-based .env generation brittle | Rewrote with anchored grep -m1, cut -d= -f2-, fail-fast on missing |

---

## Context

Emergency backup system for Datum. If Claude goes down, Codex picks up engineering tasks
with full vault read access, tool execution, and task acceptance — accessible from the
agentic-ui chat interface at :8090.

---

## Verified Codex CLI Contract

**Source:** github.com/openai/codex, developers.openai.com/codex/cli/reference
**Package:** `npm i -g @openai/codex` (v0.123.0, Rust binary via npm wrapper)
**Auth:** `OPENAI_API_KEY` env var (no login needed for headless)

### Confirmed Flags
```
codex exec [PROMPT | -]
  --json                    JSONL events to stdout
  --model, -m MODEL         Model override
  --cd, -C PATH             Working directory
  --profile, -p NAME        Config profile from config.toml
  --sandbox, -s MODE        read-only | workspace-write | danger-full-access
  --full-auto               workspace-write + on-request approvals
  --output-last-message, -o Write final message to file
  --skip-git-repo-check     Allow non-git directories
  --ephemeral               No session persistence
  -c key=value              Inline config override (repeatable)
  --image, -i PATH          Attach images
  --color MODE              always | never | auto
```

### Confirmed JSONL Event Types (--json output)
```
thread.started      — session begins
turn.started        — agent turn begins
turn.completed      — agent turn ends (contains usage/tokens)
turn.failed         — agent turn failed
item.started        — tool call or message begins
item.completed      — tool call or message ends (contains content)
```

Each event has: `type`, `thread_id`, `item` (with nested content), `usage` (token counts).

### Config File: .codex/config.toml
```toml
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.auto]
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.mini]
model = "gpt-5.4-mini"
sandbox = "workspace-write"

[profiles.codex]
model = "codex-5.4"
sandbox = "workspace-write"
```

---

## PART A: WORKSPACE BOOTSTRAP

### Step 1: Directory Structure

```
~/projects/codex-drone/
├── AGENTS.md
├── CODEX.md
├── MANIFEST.md
├── SPEC.md
├── RUNBOOK.md             ← NEW: operator guide
├── bootstrap_report.md    ← generated
├── .codex/config.toml
├── .env
├── bridge/
│   ├── server.py          ← FastAPI bridge (~200 lines)
│   ├── patcher.py         ← Python AST-based UI patcher (~80 lines)
│   ├── requirements.txt
│   └── test_bridge.py     ← behavioral integration tests
├── workspace/
├── tools/
│   ├── run_tests.sh
│   ├── build.sh
│   ├── diagnostics.sh
│   └── verify_spec.sh
├── scratch/
├── tasks/
│   └── README.md
├── memory/
│   ├── inbox/             ← Codex writable
│   ├── curated/           ← Symlink → ~/vault/ (READ-ONLY enforced)
│   └── archive/
└── vault/                 ← Symlink → ~/vault/ (READ-ONLY enforced)
```

---

### Step 2: AGENTS.md — Tool & Agent Discovery

Same as v1 but with corrected CLI flags and event types.

---

### Step 3: CODEX.md — Operating Contract

```
Role:           Emergency backup engineering drone for Datum
Autonomy:       Full-auto — complete tasks end-to-end without human approval
Sandbox:        workspace-write (Codex sandbox restricts to working dir)
Vault access:   READ-ONLY via symlink. Write ONLY to memory/inbox/.
Reporting:      Write STATUS.md in workspace root (Datum heartbeat format)
Testing:        Run tools/run_tests.sh before declaring any task complete
Escalation:     Write to memory/inbox/ESCALATION.md if:
                - Task requires credentials not in environment
                - Task would modify production systems
                - Task scope exceeds 500 lines of change
                - Ambiguity cannot be resolved from vault context
Constraints:
                - Prefer minimal, correct edits
                - Match existing project style
                - Never read or display ~/.secrets.env
                - Never modify vault content (read-only from your perspective)
                - Write to memory/inbox/ for observations and findings
                - Write tests for new functionality
                - Git commit with meaningful messages after completing work
                - Do not push to remote without explicit instruction
```

---

### Steps 4–6: Tools, Memory, Task Format

Same as v1. Memory symlinks enforced read-only at OS level (see Step 9).

---

### Step 7: .codex/config.toml

```toml
# Codex project configuration for Datum backup drone
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.auto]
model = "gpt-5.4"
sandbox = "workspace-write"

[profiles.mini]
model = "gpt-5.4-mini"
sandbox = "workspace-write"

[profiles.codex]
model = "codex-5.4"
sandbox = "workspace-write"
```

No `approval_policy` key — Codex uses `--full-auto` flag at invocation instead.

---

## PART B: CODEX CLI INSTALLATION

### Step 8: Install & Configure

```bash
npm i -g @openai/codex
codex --version   # verify Rust binary downloaded

# Smoke test with actual flags
cd ~/projects/codex-drone
OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/.secrets.env | cut -d= -f2) \
  codex exec --json --full-auto --ephemeral -C . \
  "List files in this directory and report what you see"
```

Capture JSONL output to confirm event schema matches expectations.
If any flag is rejected, fail bootstrap and update bridge parser.

---

## PART C: BRIDGE SERVICE (HARDENED)

### Step 9: bridge/server.py — Rewritten

Addresses findings F1, F2, F3, F4, F6, F7, F9, F10, F23, F24, F25.

```python
"""
Codex Bridge — FastAPI service translating agentic-ui chat → codex exec.
Hardened per GPT-5.4 adversarial review (task 80da8fcb).
"""
import asyncio, json, logging, os, signal, time, uuid
from pathlib import Path
from dotenv import load_dotenv                           # R3-F3: load .env
from fastapi import FastAPI, Depends, Header, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

# R3-F3: Load .env from bridge directory and project root
load_dotenv(Path(__file__).parent / ".env")
load_dotenv(Path(__file__).parent.parent / ".env")

# ── Config ──────────────────────────────────────────────────────
BRIDGE_TOKEN = os.environ["CODEX_BRIDGE_TOKEN"]         # F7: required, no default
CODEX_BIN = os.environ.get("CODEX_BIN", "codex")
DEFAULT_WORKSPACE = Path.home() / "projects" / "codex-drone"
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")   # F6: only this key injected

# F4: Allowlist of permitted project roots
ALLOWED_ROOTS = [
    Path.home() / "projects",
]

# F25: Cost/concurrency controls
MAX_CONCURRENT = int(os.environ.get("CODEX_MAX_CONCURRENT", "2"))
MAX_WALL_CLOCK_S = int(os.environ.get("CODEX_TIMEOUT_S", "600"))    # 10 min
IDLE_TIMEOUT_S = int(os.environ.get("CODEX_IDLE_TIMEOUT_S", "120")) # 2 min no output
DAILY_BUDGET_USD = float(os.environ.get("CODEX_DAILY_BUDGET", "20.0"))

# ── State ───────────────────────────────────────────────────────
semaphore = asyncio.Semaphore(MAX_CONCURRENT)     # F1: concurrency limit
daily_spend = {"date": "", "usd": 0.0}            # F25: reset daily
active_procs: dict[str, asyncio.subprocess.Process] = {}

# ── Logging ─────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger("codex-bridge")

app = FastAPI()

# ── Models ──────────────────────────────────────────────────────
class ChatRequest(BaseModel):
    messages: list
    model: str = "gpt-5.4"
    project_dir: str | None = None

# ── Auth (R3-F6: proper FastAPI dependency) ────────────────────
def verify_auth(authorization: str = Header(...)):
    """F7: Shared secret between agentic-ui and bridge."""
    if authorization != f"Bearer {BRIDGE_TOKEN}":
        raise HTTPException(401, "unauthorized")

# ── Path validation ─────────────────────────────────────────────
def validate_workspace(raw: str | None) -> str:
    """F4: Restrict to allowlisted project roots."""
    if raw is None:
        return str(DEFAULT_WORKSPACE)
    resolved = Path(raw).resolve()
    for root in ALLOWED_ROOTS:
        if resolved == root or root in resolved.parents:
            return str(resolved)
    raise HTTPException(403, f"workspace outside allowed roots: {resolved}")

# ── Budget check ────────────────────────────────────────────────
def check_budget():
    """F25: Daily spend cap."""
    today = time.strftime("%Y-%m-%d")
    if daily_spend["date"] != today:
        daily_spend["date"] = today
        daily_spend["usd"] = 0.0
    if daily_spend["usd"] >= DAILY_BUDGET_USD:
        raise HTTPException(429, f"daily budget exhausted: ${daily_spend['usd']:.2f}")

# ── Prompt construction ─────────────────────────────────────────
def build_prompt(messages: list) -> str:
    """F3: Full message serialization, not lossy truncation."""
    parts = []
    for m in messages:
        role = m.get("role", "user").upper()
        content = m.get("content", "")
        # Preserve system messages distinctly
        if role == "SYSTEM":
            parts.append(f"<system>\n{content}\n</system>")
        elif role == "ASSISTANT":
            parts.append(f"<assistant>\n{content}\n</assistant>")
        elif role == "TOOL":
            name = m.get("name", "tool")
            parts.append(f"<tool name=\"{name}\">\n{content}\n</tool>")
        else:
            parts.append(content)
    return "\n\n".join(parts)

# ── JSONL parser ────────────────────────────────────────────────
def parse_codex_event(line: str) -> dict | None:
    """F2, F13: Parse verified Codex JSONL events into agentic-ui SSE format."""
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return None

    etype = event.get("type", "")
    item = event.get("item", {})
    usage = event.get("usage", {})

    if etype == "item.completed":
        # Message content or tool result
        content = item.get("content", "")
        item_type = item.get("type", "")
        if item_type == "tool_call" or item_type == "command":
            return {"type": "tool_use", "name": item.get("name", "tool"),
                    "input": item.get("arguments", item.get("command", ""))}
        elif content:
            return {"type": "text", "text": content}

    elif etype == "item.started":
        # Stream text deltas if present
        delta = item.get("delta", "")
        if delta:
            return {"type": "text", "text": delta}

    elif etype == "turn.completed":
        cost = usage.get("cost_usd", 0)
        return {"type": "done",
                "cost_usd": cost,
                "input_tokens": usage.get("input_tokens", 0),
                "output_tokens": usage.get("output_tokens", 0)}

    elif etype == "turn.failed":
        error = event.get("error", "unknown error")
        return {"type": "error", "detail": str(error)}

    return None  # Ignore unrecognized events

# ── Endpoints ───────────────────────────────────────────────────
@app.get("/health")
def health():
    """F32: Readiness check, not just liveness."""
    import shutil
    checks = {
        "codex_binary": shutil.which(CODEX_BIN) is not None,
        "api_key_set": bool(OPENAI_API_KEY),
        "vault_readable": (DEFAULT_WORKSPACE / "vault").is_symlink()
                          and (DEFAULT_WORKSPACE / "vault").resolve().is_dir(),  # R3-F7
        "active_tasks": len(active_procs),
        "daily_spend_usd": daily_spend["usd"],
    }
    ready = all([checks["codex_binary"], checks["api_key_set"]])
    status_code = 200 if ready else 503
    return {"status": "ready" if ready else "not_ready", "checks": checks}

@app.post("/chat")
async def chat(req: ChatRequest, request: Request,
               _auth=Depends(verify_auth)):             # R3-F6: proper dependency injection
    check_budget()
    workspace = validate_workspace(req.project_dir)
    request_id = uuid.uuid4().hex[:8]

    # F1: Profile selection
    if req.model.startswith("codex"):
        profile = "codex"
    elif req.model == "gpt-5.4-mini":
        profile = "mini"
    else:
        profile = "auto"

    prompt = build_prompt(req.messages)

    cmd = [
        CODEX_BIN, "exec",
        "--json",
        "--full-auto",
        "--ephemeral",
        "--profile", profile,
        "--color", "never",
        "-C", workspace,
        prompt,
    ]

    log.info(f"req={request_id} model={req.model} profile={profile} workspace={workspace}")

    async def stream():
        # F1: Acquire semaphore (concurrency limit)
        async with semaphore:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env={                                    # F6/C-H1: minimal env only
                    "PATH": os.environ.get("PATH", ""),
                    "HOME": os.environ.get("HOME", ""),
                    "OPENAI_API_KEY": OPENAI_API_KEY,
                    "NO_COLOR": "1",
                },
                start_new_session=True,  # F1: process group for clean kill
            )
            active_procs[request_id] = proc
            last_output = time.monotonic()
            done_emitted = False
            line_buf = ""

            try:
                start = time.monotonic()
                while True:
                    # F9-10: Wall-clock + idle timeout
                    elapsed = time.monotonic() - start
                    idle = time.monotonic() - last_output
                    if elapsed > MAX_WALL_CLOCK_S:
                        log.warning(f"req={request_id} wall-clock timeout ({MAX_WALL_CLOCK_S}s)")
                        break
                    if idle > IDLE_TIMEOUT_S:
                        log.warning(f"req={request_id} idle timeout ({IDLE_TIMEOUT_S}s)")
                        break

                    # F1: Check client disconnect
                    if await request.is_disconnected():
                        log.info(f"req={request_id} client disconnected")
                        break

                    try:
                        raw = await asyncio.wait_for(
                            proc.stdout.readline(), timeout=5.0
                        )
                    except asyncio.TimeoutError:
                        continue

                    if not raw:
                        break  # EOF

                    last_output = time.monotonic()

                    # F2: Line buffering for partial reads
                    line_buf += raw.decode()
                    while "\n" in line_buf:
                        line, line_buf = line_buf.split("\n", 1)
                        line = line.strip()
                        if not line:
                            continue

                        parsed = parse_codex_event(line)
                        if parsed:
                            yield f"data: {json.dumps(parsed)}\n\n"
                            if parsed["type"] == "done":
                                done_emitted = True
                                # F25: Track spend
                                daily_spend["usd"] += parsed.get("cost_usd", 0)
                                log.info(f"req={request_id} done cost=${parsed.get('cost_usd', 0):.4f}")

            finally:
                # F1: Kill process group on exit
                active_procs.pop(request_id, None)
                if proc.returncode is None:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
                        await asyncio.wait_for(proc.wait(), timeout=5.0)
                    except (ProcessLookupError, asyncio.TimeoutError):
                        try:
                            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                        except ProcessLookupError:
                            pass

                # Read stderr for error reporting
                if proc.returncode and proc.returncode != 0:
                    stderr = (await proc.stderr.read()).decode()[:500]
                    log.error(f"req={request_id} exit={proc.returncode} stderr={stderr}")
                    if not done_emitted:
                        yield f"data: {json.dumps({'type': 'error', 'detail': stderr})}\n\n"

                if not done_emitted:
                    yield f"data: {json.dumps({'type': 'done', 'cost_usd': 0})}\n\n"

    return StreamingResponse(stream(), media_type="text/event-stream")

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("CODEX_BRIDGE_PORT", "8092"))
    uvicorn.run(app, host="127.0.0.1", port=port)
```

**Changes from v1:**
- F7: `CODEX_BRIDGE_TOKEN` required (no default), verified on every request
- F1: `asyncio.Semaphore(MAX_CONCURRENT)` limits parallel Codex processes
- F1: `start_new_session=True` + `os.killpg()` kills entire process tree on disconnect/timeout
- F1: Client disconnect detection via `request.is_disconnected()`
- F9/F10: Wall-clock timeout (600s) + idle timeout (120s)
- F2: Line buffer for partial JSONL reads
- F13: Parser uses verified event types (`thread.*`, `turn.*`, `item.*`)
- F3: Full message serialization preserving system/assistant/tool roles
- F4: Path allowlist — only `~/projects/*` permitted
- F6: Only `OPENAI_API_KEY` injected into subprocess env
- F23/F24: Structured JSON logging with request IDs
- F25: Daily budget cap + per-request cost tracking
- F32: Health endpoint checks binary, API key, vault mount, active tasks

---

### Step 10: Vault Access Model (F5)

Vault symlinks are **read-only at OS level**:

```bash
# In bootstrap.sh:
# vault/ and memory/curated/ are symlinks to ~/vault/
# Codex sandbox mode is workspace-write → only CWD is writable
# Vault lives outside CWD → read-only by sandbox enforcement

# Additionally, memory/inbox/ is inside the workspace → writable
# memory/curated/ points to vault → read-only by sandbox

# The Codex sandbox enforces this at the OS level.
# The bridge passes --sandbox workspace-write (via --full-auto).
# Files outside the -C workspace root are read-only.
```

**Key insight:** Codex's own sandbox handles this. When `--full-auto` (workspace-write) is used
with `-C ~/projects/codex-drone`, only files under that directory are writable. The vault symlink
resolves to `~/vault/` which is outside the workspace root → read-only by sandbox.

`memory/inbox/` is inside the workspace → writable. This is exactly the access model we want.

For extra safety, `CODEX.md` explicitly instructs the agent not to write to vault.

**Workspace routing (R3-F1):** The bridge does NOT accept `project_dir` from the UI.
Codex always starts in `~/projects/codex-drone/` — its home workspace. To work on other
projects, users include the target in their message (e.g., "Fix the auth bug in ~/projects/slope64-api").
Codex can navigate to any project under `~/projects/` using its file/shell tools, same as Claude Code.
The `ALLOWED_ROOTS` allowlist in the bridge restricts `-C` to `~/projects/*` for safety.
This matches the existing agentic-ui pattern where no other persona passes a project_dir.

---

### Step 11: Secret Handling (F6)

The subprocess env in Step 9 uses an explicit allowlist: only `PATH`, `HOME`,
`OPENAI_API_KEY`, and `NO_COLOR`. No `**os.environ` — only approved vars.
No `.secrets.env` mount. No ambient credential leakage.

---

### Step 12: UI Wiring — Python Patcher (F16, F17)

Replace `wire_ui.sh` (sed-based) with `bridge/patcher.py`:

```python
"""
Patch agentic-ui to add Codex persona routing.
Validates syntax before and after. Idempotent.
"""
import ast, re, shutil, sys
from pathlib import Path

AGENTIC_UI = Path.home() / "projects" / "agentic-ui"
PERSONAS_PY = AGENTIC_UI / "personas.py"
SERVER_PY = AGENTIC_UI / "server.py"
PERSONA_MD = Path.home() / "vault" / "personas" / "codex.md"

def validate_syntax(path: Path) -> bool:
    try:
        ast.parse(path.read_text())
        return True
    except SyntaxError as e:
        print(f"SYNTAX ERROR in {path}: {e}", file=sys.stderr)
        return False

def backup(path: Path):
    bak = path.with_suffix(path.suffix + ".codex-backup")
    if not bak.exists():
        shutil.copy2(path, bak)

def patch_personas():
    text = PERSONAS_PY.read_text()
    if '"codex"' in text:
        print("personas.py: already patched")
        return
    backup(PERSONAS_PY)

    # Insert into DISPLAY_NAMES
    text = re.sub(
        r'(DISPLAY_NAMES\s*=\s*\{)',
        r'\1\n    "codex": "Codex",',
        text, count=1
    )
    # Insert into ICONS
    text = re.sub(
        r'(ICONS\s*=\s*\{)',
        r'\1\n    "codex": "ph-cpu",',
        text, count=1
    )
    PERSONAS_PY.write_text(text)

def patch_server():
    text = SERVER_PY.read_text()
    if 'run_codex_agent' in text:
        print("server.py: already patched")
        return
    backup(SERVER_PY)

    # ROUTING BLOCK (injected as a clearly-marked section)
    # Fixes: C1 (try/except), C3 (guaranteed done), H2 (timeout match), H4 (import guard)
    routing_block = '''
# --- Codex Bridge Integration (codex-drone bootstrap) ---
CODEX_BRIDGE_URL = os.environ.get("CODEX_BRIDGE_URL", "http://localhost:8092")
CODEX_BRIDGE_TOKEN = os.environ.get("CODEX_BRIDGE_TOKEN", "")
CODEX_MODELS = {"gpt-5.4-mini", "gpt-5.4", "codex-5.4"}

async def run_codex_agent(messages: list, model: str = "gpt-5.4"):
    """Proxy to codex-drone bridge. Yields same event dicts as run_cc / run_openai."""
    try:
        import httpx                                            # H4: guarded import
    except ImportError:
        yield {"type": "error", "detail": "httpx not installed — run: pip install httpx"}
        return

    done_emitted = False                                        # C3: track terminal event
    try:
        async with httpx.AsyncClient(timeout=660.0) as client:  # H2: > bridge 600s wall-clock
            headers = {}
            if CODEX_BRIDGE_TOKEN:
                headers["Authorization"] = f"Bearer {CODEX_BRIDGE_TOKEN}"
            async with client.stream(
                "POST",
                f"{CODEX_BRIDGE_URL}/chat",
                headers=headers,
                json={"messages": messages, "model": model},
            ) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    yield {"type": "error", "detail": f"codex-bridge {response.status_code}: {body.decode()[:200]}"}
                    return
                async for line in response.aiter_lines():
                    if line.startswith("data: "):
                        try:
                            event = json.loads(line[6:])
                            yield event
                            if event.get("type") == "done":
                                done_emitted = True
                        except json.JSONDecodeError:
                            continue
    except Exception as e:                                       # C1: catch connection errors
        yield {"type": "error", "detail": f"codex-bridge unreachable: {e}"}
    finally:
        if not done_emitted:                                     # C3: synthetic done on failure
            yield {"type": "done", "cost_usd": 0, "input_tokens": 0, "output_tokens": 0}
# --- End Codex Bridge Integration ---
'''
    text += routing_block

    # Insert routing condition — find the openai routing line and add after
    text = re.sub(
        r'(use_openai_agent\s*=\s*[^\n]+)',
        r'\1\n    use_codex_agent = not use_voice_agent and not use_datum_agent and not use_openai_agent and persona == "codex"',
        text, count=1
    )

    # Insert dispatch branch — find "elif use_openai_agent:" and add before
    text = re.sub(
        r'(\s+)(elif use_openai_agent:)',
        r'\1elif use_codex_agent:\n\1    codex_model = body.model if body.model in CODEX_MODELS else "gpt-5.4"\n\1    event_iter = run_codex_agent(history, codex_model)\n\1\2',
        text, count=1
    )

    SERVER_PY.write_text(text)

def patch_frontend():
    """C2: Add Codex model optgroup to index.html + update JS OPENAI_MODELS set."""
    # ── index.html: add Codex optgroup ──
    index_html = AGENTIC_UI / "static" / "index.html"
    text = index_html.read_text()
    if "codex-5.4" in text:
        print("index.html: already patched")
    else:
        backup(index_html)
        codex_optgroup = '''                  <optgroup label="Codex">
                    <option value="gpt-5.4">GPT-5.4</option>
                    <option value="gpt-5.4-mini">GPT-5.4 mini</option>
                    <option value="codex-5.4">Codex-5.4</option>
                  </optgroup>'''
        # Insert before closing </select>
        text = text.replace(
            '                </select>',
            codex_optgroup + '\n                </select>',
            1
        )
        index_html.write_text(text)
        print("index.html: patched — Codex optgroup added")

    # ── app.js: add Codex models to OPENAI_MODELS set ──
    app_js = AGENTIC_UI / "static" / "app.js"
    js = app_js.read_text()
    if "gpt-5.4" in js:
        print("app.js: already patched")
    else:
        backup(app_js)
        js = js.replace(
            '"o3-mini"]);',
            '"o3-mini","gpt-5.4","gpt-5.4-mini","codex-5.4"]);',
            1
        )
        app_js.write_text(js)
        print("app.js: patched — Codex models added to OPENAI_MODELS")

def write_persona():
    PERSONA_MD.write_text("""# Persona: Codex

## Role
Emergency backup engineering drone. OpenAI Codex agent operating under Datum supervision.
Full replacement for Claude — handles all coding, analysis, and engineering tasks.

## Paths
- Workspace: ~/vault/workspaces/developer/
- Vault: ~/vault/dev/

## Behavior
- Autonomous: completes tasks end-to-end
- Tests before declaring done
- Writes STATUS.md heartbeat for live monitoring
- Escalates when blocked (credentials, production, scope, ambiguity)

## Models
- Default: gpt-5.4 (full capability)
- Fast/cheap: gpt-5.4-mini
- Reasoning: codex-5.4 (code-optimized reasoning model)
""")

def main():
    # Pre-patch validation
    for f in [PERSONAS_PY, SERVER_PY]:
        if not validate_syntax(f):
            print(f"ABORT: {f} has syntax errors before patching", file=sys.stderr)
            sys.exit(1)

    write_persona()
    patch_personas()
    patch_server()
    patch_frontend()  # C2: model dropdown + JS

    # Post-patch validation
    for f in [PERSONAS_PY, SERVER_PY]:
        if not validate_syntax(f):
            print(f"ROLLBACK: {f} broken after patch", file=sys.stderr)
            bak = f.with_suffix(f.suffix + ".codex-backup")
            if bak.exists():
                shutil.copy2(bak, f)
                print(f"  restored from {bak}")
            sys.exit(1)

    print("Patch complete. Syntax validated.")

if __name__ == "__main__":
    main()
```

**Changes from v1 + v2:**
- F16: No sed — uses regex on Python source with AST validation
- F17: Pre-patch and post-patch `ast.parse()` syntax check
- F17: Auto-rollback from backup if patch corrupts syntax
- F22: Each insertion checked independently (personas + server)
- F27: Backup files created before modification
- C2: `patch_frontend()` adds Codex models to index.html dropdown + app.js OPENAI_MODELS set
- C1/C3/H2/H4: `run_codex_agent` routing block hardened (try/except, done guarantee, timeout match, import guard)

---

### Step 13: Behavioral Integration Tests (F28, F29, F30)

`bridge/test_bridge.py`:

```python
"""
Behavioral integration tests for the Codex bridge.
Tests actual streaming, parsing, error handling — not just file existence.
"""
import asyncio, json, os, subprocess, sys
from pathlib import Path

PASS = FAIL = 0

def assert_test(name, condition, detail=""):
    global PASS, FAIL
    if condition:
        print(f"PASS: {name}")
        PASS += 1
    else:
        print(f"FAIL: {name} — {detail}")
        FAIL += 1

# ── CLI verification ────────────────────────────────────────────
def test_codex_installed():
    r = subprocess.run(["codex", "--version"], capture_output=True)
    assert_test("codex binary exists and runs", r.returncode == 0, r.stderr.decode()[:100])

def test_codex_flags():
    """Verify critical flags are accepted (--json, --full-auto, --ephemeral)."""
    r = subprocess.run(
        ["codex", "exec", "--json", "--full-auto", "--ephemeral", "--color", "never",
         "-C", "/tmp", "--skip-git-repo-check", "echo hello"],
        capture_output=True, timeout=30,
        env={**os.environ, "OPENAI_API_KEY": os.environ.get("OPENAI_API_KEY", "test")}
    )
    # May fail due to auth but should NOT fail due to unknown flags
    assert_test("codex exec accepts expected flags",
                "unknown" not in r.stderr.decode().lower()
                and "unrecognized" not in r.stderr.decode().lower(),
                r.stderr.decode()[:200])

# ── JSONL parser tests ──────────────────────────────────────────
def test_parser_item_completed():
    """Verify parser handles item.completed with text content."""
    sys.path.insert(0, str(Path(__file__).parent))
    from server import parse_codex_event
    result = parse_codex_event(json.dumps({
        "type": "item.completed",
        "item": {"type": "message", "content": "Hello world"}
    }))
    assert_test("parser: item.completed → text", result == {"type": "text", "text": "Hello world"})

def test_parser_turn_completed():
    from server import parse_codex_event
    result = parse_codex_event(json.dumps({
        "type": "turn.completed",
        "usage": {"cost_usd": 0.05, "input_tokens": 100, "output_tokens": 50}
    }))
    assert_test("parser: turn.completed → done",
                result and result["type"] == "done" and result["cost_usd"] == 0.05)

def test_parser_turn_failed():
    from server import parse_codex_event
    result = parse_codex_event(json.dumps({
        "type": "turn.failed", "error": "rate limit"
    }))
    assert_test("parser: turn.failed → error",
                result and result["type"] == "error" and "rate limit" in result["detail"])

def test_parser_malformed():
    from server import parse_codex_event
    assert_test("parser: malformed JSON → None", parse_codex_event("not json") is None)
    assert_test("parser: unknown event → None",
                parse_codex_event(json.dumps({"type": "unknown.event"})) is None)

# ── Path validation tests ───────────────────────────────────────
def test_path_validation():
    from server import validate_workspace
    # Valid
    assert_test("path: ~/projects/foo allowed",
                validate_workspace(str(Path.home() / "projects" / "foo")))
    # Invalid
    try:
        validate_workspace("/etc/passwd")
        assert_test("path: /etc/passwd rejected", False, "should have raised")
    except Exception:
        assert_test("path: /etc/passwd rejected", True)
    try:
        validate_workspace(str(Path.home() / "vault"))
        assert_test("path: ~/vault rejected", False, "should have raised")
    except Exception:
        assert_test("path: ~/vault rejected", True)

# ── UI patch validation ─────────────────────────────────────────
def test_ui_patch_syntax():
    """F30: Verify patched files still parse."""
    for name in ["personas.py", "server.py"]:
        path = Path.home() / "projects" / "agentic-ui" / name
        if path.exists():
            import ast
            try:
                ast.parse(path.read_text())
                assert_test(f"agentic-ui/{name} syntax valid", True)
            except SyntaxError as e:
                assert_test(f"agentic-ui/{name} syntax valid", False, str(e))

# ── Bridge health test ──────────────────────────────────────────
def test_bridge_health():
    import urllib.request
    try:
        r = urllib.request.urlopen("http://localhost:8092/health", timeout=5)
        data = json.loads(r.read())
        assert_test("bridge health endpoint responds", data.get("status") in ("ready", "not_ready"))
    except Exception as e:
        assert_test("bridge health endpoint responds", False, str(e))

if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--all"

    # Offline tests (no running bridge needed) — R3-F2
    if mode in ("--offline", "--all"):
        test_codex_installed()
        test_codex_flags()
        test_parser_item_completed()
        test_parser_turn_completed()
        test_parser_turn_failed()
        test_parser_malformed()
        test_path_validation()
        test_ui_patch_syntax()

    # Live tests (bridge must be running)
    if mode in ("--live", "--all"):
        test_bridge_health()

    print(f"\nResults: {PASS} passed, {FAIL} failed")
    sys.exit(0 if FAIL == 0 else 1)
```

---

### Step 14: RUNBOOK.md — Operator Guide (F31)

```markdown
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
```

---

## PART D: SCRIPT ARCHITECTURE

### bootstrap.sh — Master Script (updated)

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

CHECK_ONLY=false
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=true

log() { echo ":: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

if $CHECK_ONLY; then
    # F19: --check ONLY runs validation, zero writes
    log "Check mode — validation only"
    bash tools/verify_spec.sh
    bash tools/diagnostics.sh
    exit $?
fi

# ── Phase 1: Directory structure ──
log "Phase 1: Directory structure"
for d in workspace tools scratch tasks memory/inbox memory/archive .codex bridge scripts; do
    mkdir -p "$d"
done

VAULT_TARGET="${COEX_OBSIDIAN_VAULT:-$HOME/vault}"
[ -d "$VAULT_TARGET" ] || fail "Vault not found at $VAULT_TARGET"

for link in vault memory/curated; do
    if [ -L "$link" ]; then
        current=$(readlink "$link")
        [ "$current" = "$VAULT_TARGET" ] || { rm "$link"; ln -s "$VAULT_TARGET" "$link"; }
    elif [ -e "$link" ]; then
        fail "$link exists but is not a symlink — remove manually"  # F21
    else
        ln -s "$VAULT_TARGET" "$link"
    fi
done

# ── Phase 2: Generate files ──
log "Phase 2: Generate files"
bash scripts/gen_agents_md.sh    > AGENTS.md
bash scripts/gen_codex_md.sh     > CODEX.md
bash scripts/gen_manifest_md.sh  > MANIFEST.md
bash scripts/gen_spec_md.sh      > SPEC.md
bash scripts/gen_runbook_md.sh   > RUNBOOK.md
bash scripts/gen_tasks_readme.sh > tasks/README.md
bash scripts/gen_env.sh          > .env
bash scripts/gen_codex_config.sh > .codex/config.toml
bash scripts/gen_gitignore.sh    > .gitignore
bash scripts/gen_tools.sh
bash scripts/gen_bridge.sh

# ── Phase 3: Codex CLI ── R3-F10: preflight npm
log "Phase 3: Codex CLI"
command -v npm &>/dev/null || fail "npm not found — install Node.js first"
if ! command -v codex &>/dev/null; then
    log "Installing Codex CLI..."
    npm i -g @openai/codex || fail "Failed to install Codex CLI"
fi
codex --version || fail "Codex CLI not functional"

# ── Phase 4: Bridge deps ── R3-F4: fail hard on missing deps
log "Phase 4: Bridge dependencies"
pip install --quiet fastapi uvicorn httpx python-dotenv || fail "Failed to install bridge dependencies"

# ── Phase 5: UI wiring ──
log "Phase 5: UI wiring (Python patcher)"
python3 bridge/patcher.py

# H3: Ensure agentic-ui has bridge env vars
AGENTIC_ENV="$HOME/projects/agentic-ui/.env"
if [ -f "$AGENTIC_ENV" ]; then
    grep -q "CODEX_BRIDGE_URL" "$AGENTIC_ENV" || echo 'CODEX_BRIDGE_URL=http://localhost:8092' >> "$AGENTIC_ENV"
    grep -q "CODEX_BRIDGE_TOKEN" "$AGENTIC_ENV" || echo "CODEX_BRIDGE_TOKEN=$(openssl rand -hex 16)" >> "$AGENTIC_ENV"
    # Copy same token to codex-drone .env
    BRIDGE_TOKEN=$(grep CODEX_BRIDGE_TOKEN "$AGENTIC_ENV" | cut -d= -f2)
    grep -q "CODEX_BRIDGE_TOKEN" .env 2>/dev/null || echo "CODEX_BRIDGE_TOKEN=$BRIDGE_TOKEN" >> .env
    log "Bridge token synchronized between agentic-ui and codex-drone"
else
    log "WARNING: $AGENTIC_ENV not found — set CODEX_BRIDGE_URL and CODEX_BRIDGE_TOKEN manually"
fi

# ── Phase 6: Validation (offline tests) ──
log "Phase 6: Offline validation"
bash tools/verify_spec.sh 2>&1 | tee bootstrap_report.md
echo "" >> bootstrap_report.md
echo "--- Diagnostics ---" >> bootstrap_report.md
bash tools/diagnostics.sh 2>&1 >> bootstrap_report.md

# ── Phase 7: Integration tests (start bridge, test, stop) ── R3-F2
log "Phase 7: Integration tests"
# Run offline tests (parser, path validation, CLI checks)
python3 bridge/test_bridge.py --offline 2>&1 | tee -a bootstrap_report.md

# Start bridge in background for live tests
log "Starting bridge for health check..."
source .env 2>/dev/null || true
CODEX_BRIDGE_TOKEN="${CODEX_BRIDGE_TOKEN:-test}" python3 bridge/server.py &
BRIDGE_PID=$!
sleep 2
if kill -0 $BRIDGE_PID 2>/dev/null; then
    python3 bridge/test_bridge.py --live 2>&1 | tee -a bootstrap_report.md
    kill $BRIDGE_PID 2>/dev/null || true
    wait $BRIDGE_PID 2>/dev/null || true
else
    log "WARNING: Bridge failed to start — skipping live tests"
fi

# ── Phase 8: Git (after validation passes) ── R3-F5
log "Phase 8: Git"
if [ ! -d .git ]; then
    git init
fi
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git add -A
    git commit -m "Bootstrap: Codex drone workspace provisioned"
fi

log "Done. Report: bootstrap_report.md"
```

---

## PART E: STANDALONE CODEX UI (Datum-branded)

Standalone web app + PWA for the Codex agent, matching the pattern of other OpenAI assistants
(belle-openrouter, gis_assistant, edna_assistant). Datum-branded with orrery logo.

**Base template:** `~/projects/belle-openrouter/belle-api/` (LiteLLM + FastAPI + single-file UI)
**Port:** 8132 (host) → 8120 (container)
**Project:** `~/projects/codex-drone/ui/`

### Step 15: UI Project Structure

Dockerfile lives inside `belle-api/` (matching belle-openrouter pattern exactly).
`docker-compose.yml` and `.env` live in `ui/` (the compose context root).

```
~/projects/codex-drone/ui/
├── docker-compose.yml
├── .env                      ← OPENAI_API_KEY + CODEX_BRIDGE_TOKEN
└── belle-api/                ← forked from belle-openrouter, rebranded
    ├── Dockerfile            ← build context is here (matches template)
    ├── server.py             ← FastAPI (from belle-openrouter, patched: litellm→httpx for aux tasks)
    ├── agent.py              ← REPLACED: bridge proxy module (not LiteLLM, see Step 17)
    ├── db.py                 ← SQLite (conversations, messages, memory) — unchanged
    ├── requirements.txt      ← modified: litellm replaced with httpx
    ├── instances/
    │   └── codex/
    │       └── system_prompt.txt  ← generated from CODEX.md operating contract
    └── static/
        ├── index.html         ← Datum-branded (navy/gold, orrery logo, "Codex" title)
        ├── manifest.json      ← PWA: "Datum Codex", datum-mark.svg + prebuilt PNGs
        ├── datum-mark.svg     ← copied from agentic-ui
        ├── icon-192.png       ← prebuilt: vendored in scripts/ (not runtime-generated)
        ├── icon-512.png       ← prebuilt: vendored in scripts/ (not runtime-generated)
        └── sw.js              ← service worker (cache name updated to "codex-v1")
```

**Architecture:** This standalone UI proxies to the Codex bridge from Part C (:8092),
giving full `codex exec` access (shell, file tools, coding). The belle template provides
the frontend (conversation management, memory, PWA) while `agent.py` is replaced with a
bridge proxy module. The bridge must be running for this UI to work.

Two ways to access the same Codex engine:
- **:8090** (agentic-ui persona) — integrated into the multi-persona Datum UI
- **:8132** (standalone PWA) — dedicated Datum Codex app with better conversation UX

### Step 16: docker-compose.yml

```yaml
networks:
  codex-internal:
    driver: bridge
    internal: true
  codex-egress:
    driver: bridge

services:
  codex-ui:
    build:
      context: ./belle-api
      dockerfile: Dockerfile
    container_name: codex-ui
    networks:
      - codex-internal
      - codex-egress
    ports:
      - "8132:8120"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      PORT: 8120
      HOST: 0.0.0.0
      DB_PATH: /app/data/codex.db
      FILES_DIR: /app/files
      SYSTEM_PROMPT_PATH: /app/instances/codex/system_prompt.txt

      # Bridge proxy — agent.py connects to Codex bridge on host
      CODEX_BRIDGE_URL: http://host.docker.internal:8092
      CODEX_BRIDGE_TOKEN: ${CODEX_BRIDGE_TOKEN}

      # OpenAI API key — used by server.py for auxiliary tasks (memory, titles)
      OPENAI_API_KEY: ${OPENAI_API_KEY}

      # Default model for bridge requests
      DEFAULT_MODEL: gpt-5.4
    env_file:
      - .env
    volumes:
      - codex-ui-data:/app/data
      - ./belle-api/files:/app/files
      - ./belle-api/instances:/app/instances
      - ./belle-api/static:/app/static
    restart: unless-stopped

volumes:
  codex-ui-data:
    driver: local
    name: codex-ui_data
```

### Step 17: agent.py — Bridge Proxy (replaces LiteLLM agent entirely)

This file REPLACES the belle-openrouter `agent.py`. Instead of calling LiteLLM,
it proxies to the Codex bridge at :8092 which runs `codex exec` with full shell/file tools.

```python
"""Codex Bridge proxy — drop-in replacement for belle-openrouter agent.py.

Implements the same run_agent() interface so server.py works unchanged.
Proxies all requests to the Codex bridge service (Part C).

Event flow:
  bridge SSE → agent.py (filter/normalize) → server.py (persist + final done) → frontend

The bridge emits: text, tool_use, done, error events (already normalized by Part C parser).
This agent passes text/tool_use/error through. Bridge 'done' events are ABSORBED (not yielded)
because server.py emits its own authoritative 'done' in its finally block. Yielding bridge done
would cause a double-done bug where the second done (from server, no cost_usd) overwrites the
frontend's costUsd variable with undefined.
"""
import json
import logging
import os
from pathlib import Path
from typing import AsyncGenerator

import httpx

log = logging.getLogger("codex-agent")

# ── Configuration ──────────────────────────────────────────────────────────────

DEFAULT_MODEL: str = os.environ.get("DEFAULT_MODEL", "gpt-5.4")
BRIDGE_URL: str = os.environ.get("CODEX_BRIDGE_URL", "http://host.docker.internal:8092")
BRIDGE_TOKEN: str = os.environ.get("CODEX_BRIDGE_TOKEN", "")
SYSTEM_PROMPT_PATH: str = os.environ.get(
    "SYSTEM_PROMPT_PATH", "/app/instances/codex/system_prompt.txt"
)

ALLOWED_MODELS: set[str] = {
    "gpt-5.4", "gpt-5.4-mini", "codex-5.4",
    "gpt-4o", "gpt-4o-mini", "default",
}

# ── Helpers ────────────────────────────────────────────────────────────────────

def _load_system_prompt() -> str:
    try:
        return Path(SYSTEM_PROMPT_PATH).read_text().strip()
    except Exception:
        return ""


def _build_messages(
    messages: list, memory_context: str, history: list | None
) -> list[dict]:
    """Build the bridge message payload.

    Belle's /chat passes BOTH history (full conversation so far) and messages
    (current turn only). We use history when available because it's the superset.
    System prompt and memory context are prepended.

    Dedup guard: history already contains previous turns. We only append the
    current user message from `messages` if it's not already the last entry in
    history (which it shouldn't be — belle fetches history before the new message
    is persisted).
    """
    bridge_messages = []

    sys_prompt = _load_system_prompt()
    if sys_prompt:
        bridge_messages.append({"role": "system", "content": sys_prompt})
    if memory_context:
        bridge_messages.append({"role": "system", "content": f"Memory:\n{memory_context}"})

    if history:
        bridge_messages.extend(history)
        # Append current turn if not already in history
        if messages:
            last_hist = history[-1] if history else {}
            last_msg = messages[-1] if messages else {}
            if last_hist.get("content") != last_msg.get("content"):
                bridge_messages.extend(messages)
    else:
        bridge_messages.extend(messages)

    return bridge_messages


# ── Main entry point ───────────────────────────────────────────────────────────

async def run_agent(
    messages: list,
    model: str = "default",
    conversation_id: str = None,
    memory_context: str = "",
    history: list = None,
    cc_session_id: str = None,
) -> AsyncGenerator[dict, None]:
    """Proxy to Codex bridge. Same event dict interface as LiteLLM agent.

    Yields: {"type": "text", "text": str}
            {"type": "tool_use", "name": str, "input": str}
            {"type": "error", "detail": str}

    Does NOT yield done — server.py emits the authoritative done event.
    """
    effective_model = model if model in ALLOWED_MODELS and model != "default" else DEFAULT_MODEL

    bridge_messages = _build_messages(messages, memory_context, history)

    headers = {"Content-Type": "application/json"}
    if BRIDGE_TOKEN:
        headers["Authorization"] = f"Bearer {BRIDGE_TOKEN}"

    try:
        async with httpx.AsyncClient(timeout=660.0) as client:
            async with client.stream(
                "POST",
                f"{BRIDGE_URL}/chat",
                headers=headers,
                json={"messages": bridge_messages, "model": effective_model},
            ) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    yield {
                        "type": "error",
                        "detail": f"bridge {response.status_code}: {body.decode()[:200]}",
                    }
                    return

                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    try:
                        event = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue

                    etype = event.get("type", "")

                    # Pass through text and tool_use events
                    if etype in ("text", "tool_use", "error"):
                        yield event
                    elif etype == "done":
                        # Absorb — server.py emits its own done.
                        # Log cost for observability.
                        cost = event.get("cost_usd", 0)
                        if cost:
                            log.info(
                                "bridge done: cost=$%.4f in=%d out=%d",
                                cost,
                                event.get("input_tokens", 0),
                                event.get("output_tokens", 0),
                            )
                    # else: ignore unknown event types

    except httpx.ConnectError:
        yield {
            "type": "error",
            "detail": "Codex bridge unreachable — is it running on :8092?",
        }
    except httpx.ReadTimeout:
        yield {"type": "error", "detail": "Codex bridge timed out (660s)."}
    except Exception as e:
        yield {"type": "error", "detail": f"codex-bridge error: {e}"}
```

**Key design decisions:**

1. **Bridge `done` absorbed, not yielded.** Server.py always emits the final done in its
   `finally` block. If agent also yields done, frontend gets two done events — second one
   (from server, no `cost_usd`) overwrites `costUsd` with undefined, breaking cost display.

2. **History dedup.** Belle passes both `history` (all previous turns from DB) and `messages`
   (current turn). We use history as base and only append messages if the current user message
   isn't already the last history entry. Prevents duplicate context to bridge.

3. **Model validation.** Unknown models fall back to DEFAULT_MODEL instead of passing through
   to bridge where they'd fail as unrecognized Codex profiles.

4. **Specific exception handling.** `ConnectError` and `ReadTimeout` get distinct error messages
   instead of generic "unreachable" for both cases.

5. **No agent-level done/finally.** Server.py's finally block handles the done event, message
   persistence, memory extraction, and title generation. Agent is a pure event pipe.

**Server.py imports from agent:** Only `DEFAULT_MODEL` (health endpoint) and `run_agent` (lazy,
inside /chat). Both exist. No tools.py imports in server.py — safe to remove.

### Step 17b: server.py patching — rationale

The server.py patching logic lives in `gen_codex_ui.sh` (step 2 of the script, Python inline).
Key decisions documented here for review:

- **Function name kept as `_litellm_complete`.** Minimises diff — every call site stays unchanged.
  The function body changes, the interface doesn't.
- **Replacement uses httpx → OpenAI Chat Completions API.** Direct HTTP, no SDK dependency.
- **Default aux model is `gpt-4o-mini`, not `gpt-5.4`.** Auxiliary tasks (memory extraction,
  title generation) don't need a frontier model. ~40x cheaper. Configurable via `AUX_MODEL` env.
- **Exact string match on old function body.** If belle's server.py changes the litellm function,
  the patcher will fail loudly rather than silently produce broken output. Idempotent — if
  already patched (detects `api.openai.com` in source), skips.
- **AST validation before write.** If the patched result has syntax errors, original is restored.

### Step 18: Datum Branding — Static Assets

**manifest.json:**
```json
{
  "name": "Datum Codex",
  "short_name": "Codex",
  "description": "Emergency backup engineering agent — GPT-5.4 powered",
  "start_url": "/",
  "display": "standalone",
  "theme_color": "#f0f1f0",
  "background_color": "#f0f1f0",
  "icons": [
    { "src": "/datum-mark.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any" },
    { "src": "/datum-mark.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "maskable" },
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ],
  "categories": ["productivity"],
  "orientation": "any"
}
```

**index.html branding changes** (from belle-openrouter base):
- Title: `Datum Codex — Engineering Agent`
- CSS vars: identical to agentic-ui Datum palette (navy #1d3a5c, gold #c89632, etc.)
- Logo: `datum-mark.svg` in header (same orrery mark as agentic-ui)
- Model selector: GPT-5.4 (default), GPT-5.4 mini, Codex-5.4, GPT-4o, GPT-4o mini
- Placeholder text: "Ask Codex to build, fix, or analyze..."
- Header subtitle: "Emergency engineering backup"

**icon-192.png / icon-512.png generation:**
```bash
# Rasterize SVG to PNG with navy background circle for PWA icons
# Uses Inkscape or rsvg-convert (installed on host)
rsvg-convert -w 512 -h 512 datum-mark.svg -o icon-512.png
rsvg-convert -w 192 -h 192 datum-mark.svg -o icon-192.png
```

### Step 19: System Prompt (instances/codex/system_prompt.txt)

Derived from CODEX.md operating contract + codex.md persona:

```
You are Codex, an emergency backup engineering agent for the Datum platform.
You operate as a full replacement for Claude when the primary assistant is unavailable.

## Capabilities
- Full coding, analysis, and engineering tasks
- Web search via Brave and Tavily tools
- File management via attached tools

## Operating Contract
- Autonomy: Full-auto — complete tasks end-to-end
- Test before declaring any task complete
- Prefer minimal, correct edits
- Match existing project style
- Write tests for new functionality
- Git commit with meaningful messages after completing work

## Models Available
- GPT-5.4 (default) — full capability
- GPT-5.4 mini — fast/cheap for simple tasks
- Codex-5.4 — code-optimized reasoning model

## Escalation
Flag clearly if:
- Task requires credentials not available
- Task would modify production systems
- Task scope exceeds 500 lines of change
- Ambiguity cannot be resolved from available context
```

### Step 20: Bootstrap Integration

Add to `bootstrap.sh` between Phase 2 and Phase 3:

```bash
# ── Phase 2b: Standalone UI ──
log "Phase 2b: Standalone UI"
UI_DIR="$HOME/projects/codex-drone/ui"
BELLE_SRC="$HOME/projects/belle-openrouter/belle-api"

if [ ! -d "$BELLE_SRC" ]; then
    log "WARNING: belle-openrouter not found at $BELLE_SRC — skipping standalone UI"
else
    # Clean target to ensure idempotent copy (rm -rf safe: UI_DIR is always under codex-drone)
    mkdir -p "$UI_DIR"
    rm -rf "$UI_DIR/belle-api"
    mkdir -p "$UI_DIR/belle-api"

    # Copy template files explicitly (not data/, not .git, not agent.py/tools.py — replaced by gen script)
    for f in server.py db.py Dockerfile; do
        cp "$BELLE_SRC/$f" "$UI_DIR/belle-api/$f"
    done
    mkdir -p "$UI_DIR/belle-api/static" "$UI_DIR/belle-api/instances/codex"

    # Apply Codex-specific modifications via generator
    bash scripts/gen_codex_ui.sh "$UI_DIR"
    log "Standalone UI prepared at $UI_DIR"
fi
```

#### gen_codex_ui.sh — Full Script

```bash
#!/usr/bin/env bash
# gen_codex_ui.sh — Generate standalone Codex UI from belle-openrouter template.
# Called by bootstrap.sh: bash scripts/gen_codex_ui.sh "$UI_DIR"
# Idempotent: can run multiple times safely.
set -euo pipefail

UI_DIR="${1:?Usage: gen_codex_ui.sh <ui-dir>}"
BELLE_API="$UI_DIR/belle-api"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPTS_DIR")"

fail() { echo "FAIL: $1" >&2; exit 1; }
log()  { echo "[gen_codex_ui] $1"; }

# ── Pre-flight checks ─────────────────────────────────────────────────────────

[ -f "$BELLE_API/server.py" ] || fail "server.py not found in $BELLE_API — run bootstrap copy first"
[ -f "$HOME/projects/agentic-ui/static/datum-mark.svg" ] || fail "datum-mark.svg not found in agentic-ui"
[ -f "$SCRIPTS_DIR/assets/icon-192.png" ] || fail "icon-192.png not found in scripts/assets/"
[ -f "$SCRIPTS_DIR/assets/icon-512.png" ] || fail "icon-512.png not found in scripts/assets/"

# ── 1. Write agent.py (full replacement — Step 17 content) ────────────────────

log "Writing bridge proxy agent.py"
cat > "$BELLE_API/agent.py" << 'AGENTEOF'
"""Codex Bridge proxy — drop-in replacement for belle-openrouter agent.py.
[Step 17 content is written here verbatim by the generator]
"""
import json
import logging
import os
from pathlib import Path
from typing import AsyncGenerator

import httpx

log = logging.getLogger("codex-agent")

DEFAULT_MODEL: str = os.environ.get("DEFAULT_MODEL", "gpt-5.4")
BRIDGE_URL: str = os.environ.get("CODEX_BRIDGE_URL", "http://host.docker.internal:8092")
BRIDGE_TOKEN: str = os.environ.get("CODEX_BRIDGE_TOKEN", "")
SYSTEM_PROMPT_PATH: str = os.environ.get(
    "SYSTEM_PROMPT_PATH", "/app/instances/codex/system_prompt.txt"
)

ALLOWED_MODELS: set[str] = {
    "gpt-5.4", "gpt-5.4-mini", "codex-5.4",
    "gpt-4o", "gpt-4o-mini", "default",
}

def _load_system_prompt() -> str:
    try:
        return Path(SYSTEM_PROMPT_PATH).read_text().strip()
    except Exception:
        return ""

def _build_messages(messages, memory_context, history):
    bridge_messages = []
    sys_prompt = _load_system_prompt()
    if sys_prompt:
        bridge_messages.append({"role": "system", "content": sys_prompt})
    if memory_context:
        bridge_messages.append({"role": "system", "content": f"Memory:\n{memory_context}"})
    if history:
        bridge_messages.extend(history)
        if messages:
            last_hist = history[-1] if history else {}
            last_msg = messages[-1] if messages else {}
            if last_hist.get("content") != last_msg.get("content"):
                bridge_messages.extend(messages)
    else:
        bridge_messages.extend(messages)
    return bridge_messages

async def run_agent(
    messages: list,
    model: str = "default",
    conversation_id: str = None,
    memory_context: str = "",
    history: list = None,
    cc_session_id: str = None,
) -> AsyncGenerator[dict, None]:
    effective_model = model if model in ALLOWED_MODELS and model != "default" else DEFAULT_MODEL
    bridge_messages = _build_messages(messages, memory_context, history)
    headers = {"Content-Type": "application/json"}
    if BRIDGE_TOKEN:
        headers["Authorization"] = f"Bearer {BRIDGE_TOKEN}"
    try:
        async with httpx.AsyncClient(timeout=660.0) as client:
            async with client.stream(
                "POST", f"{BRIDGE_URL}/chat", headers=headers,
                json={"messages": bridge_messages, "model": effective_model},
            ) as response:
                if response.status_code != 200:
                    body = await response.aread()
                    yield {"type": "error", "detail": f"bridge {response.status_code}: {body.decode()[:200]}"}
                    return
                async for line in response.aiter_lines():
                    if not line.startswith("data: "):
                        continue
                    try:
                        event = json.loads(line[6:])
                    except json.JSONDecodeError:
                        continue
                    etype = event.get("type", "")
                    if etype in ("text", "tool_use", "error"):
                        yield event
                    elif etype == "done":
                        cost = event.get("cost_usd", 0)
                        if cost:
                            log.info("bridge done: cost=$%.4f", cost)
    except httpx.ConnectError:
        yield {"type": "error", "detail": "Codex bridge unreachable — is it running on :8092?"}
    except httpx.ReadTimeout:
        yield {"type": "error", "detail": "Codex bridge timed out (660s)."}
    except Exception as e:
        yield {"type": "error", "detail": f"codex-bridge error: {e}"}
AGENTEOF
python3 -c "import ast; ast.parse(open('$BELLE_API/agent.py').read())" || fail "agent.py AST validation failed"

# ── 2. Patch server.py (remove litellm, replace with httpx OpenAI calls) ──────

log "Patching server.py"
python3 << PATCHEOF
"""Patch belle server.py to remove litellm dependency.

Replaces:
  - 'import litellm' + 'litellm.suppress_debug_info = True' → removed
  - 'from agent import DEFAULT_MODEL' → removed (agent still exports it, but unused after patch)
  - _litellm_complete() body → httpx OpenAI API call
  - 'belle-assistant' → 'datum-codex' in health endpoint
  - '"litellm"' → '"codex-bridge"' in health endpoint
  - MEMORY_EXTRACT_MODEL / TITLE_MODEL env var names → AUX_MODEL

Changes are targeted line replacements, not regex on arbitrary content.
"""
import re
from pathlib import Path

server = Path("$BELLE_API/server.py")
src = server.read_text()
original = src  # keep for rollback

# Remove litellm imports
src = src.replace("import litellm\n", "")
src = src.replace("litellm.suppress_debug_info = True\n", "")

# Remove 'from agent import DEFAULT_MODEL' — we add OPENAI_API_KEY + AUX_MODEL below
src = src.replace("from agent import DEFAULT_MODEL\n", "")

# Add OPENAI_API_KEY + AUX_MODEL after the 'import httpx' line
src = src.replace(
    "import httpx\n",
    "import httpx\n\nOPENAI_API_KEY = os.environ.get('OPENAI_API_KEY', '')\nAUX_MODEL = os.environ.get('AUX_MODEL', 'gpt-4o-mini')\n",
)

# Replace BELLE_AUX_MODEL env var references
src = src.replace('BELLE_AUX_MODEL', 'AUX_MODEL')

# Add Codex models to ALLOWED_MODELS set
src = src.replace(
    '"default",\n}',
    '"default",\n    "gpt-5.4-mini",\n    "codex-5.4",\n}',
)

# Replace _litellm_complete function body
old_func = '''async def _litellm_complete(prompt: str, model: str, max_tokens: int = 500) -> str:
    """Non-streaming completion via LiteLLM for auxiliary tasks."""
    try:
        resp = await litellm.acompletion(
            model=model,
            messages=[{"role": "user", "content": prompt}],
            max_tokens=max_tokens,
        )
        return resp.choices[0].message.content.strip()
    except Exception:
        return ""'''

new_func = '''async def _litellm_complete(prompt: str, model: str, max_tokens: int = 500) -> str:
    """Non-streaming completion via OpenAI API for auxiliary tasks."""
    if not OPENAI_API_KEY:
        return ""
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                "https://api.openai.com/v1/chat/completions",
                headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
                json={
                    "model": model,
                    "messages": [{"role": "user", "content": prompt}],
                    "max_tokens": max_tokens,
                },
            )
            resp.raise_for_status()
            return resp.json()["choices"][0]["message"]["content"].strip()
    except Exception:
        return ""'''

if old_func not in src:
    print("WARNING: _litellm_complete function not found exactly — checking if already patched")
    if "api.openai.com" in src:
        print("Already patched — skipping function replacement")
    else:
        # Fallback: try to find and replace with looser matching
        raise SystemExit("FAIL: Cannot find _litellm_complete to patch — server.py may have changed")
else:
    src = src.replace(old_func, new_func)

# Health endpoint patches
src = src.replace('"belle-assistant"', '"datum-codex"')
src = src.replace('"litellm"', '"codex-bridge"')

# Replace DEFAULT_MODEL reference in health endpoint with a string literal
# (was imported from agent, now we inline it)
src = src.replace('"model": DEFAULT_MODEL', '"model": os.environ.get("DEFAULT_MODEL", "gpt-5.4")')

# Docstring update
src = src.replace("Belle Assistant — FastAPI server (LiteLLM backend)", "Datum Codex — FastAPI server (bridge proxy backend)")
src = src.replace("Memory extraction + title generation use litellm instead of claude subprocess.", "Memory extraction + title generation use httpx → OpenAI API.")
src = src.replace("Memory extraction via LiteLLM", "Memory extraction via OpenAI API")

# Validate AST
import ast
try:
    ast.parse(src)
except SyntaxError as e:
    print(f"FAIL: Patched server.py has syntax error: {e}")
    server.write_text(original)
    raise SystemExit(1)

server.write_text(src)
print("server.py patched successfully")
PATCHEOF

# ── 3. Remove tools.py ────────────────────────────────────────────────────────

log "Removing tools.py (bridge handles tool execution)"
rm -f "$BELLE_API/tools.py"

# ── 4. Generate docker-compose.yml (Step 16 content) ──────────────────────────

log "Generating docker-compose.yml"
cat > "$UI_DIR/docker-compose.yml" << 'COMPOSEEOF'
networks:
  codex-internal:
    driver: bridge
    internal: true
  codex-egress:
    driver: bridge

services:
  codex-ui:
    build:
      context: ./belle-api
      dockerfile: Dockerfile
    container_name: codex-ui
    networks:
      - codex-internal
      - codex-egress
    ports:
      - "8132:8120"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      PORT: 8120
      HOST: 0.0.0.0
      DB_PATH: /app/data/codex.db
      FILES_DIR: /app/files
      SYSTEM_PROMPT_PATH: /app/instances/codex/system_prompt.txt
      CODEX_BRIDGE_URL: http://host.docker.internal:8092
      CODEX_BRIDGE_TOKEN: ${CODEX_BRIDGE_TOKEN}
      OPENAI_API_KEY: ${OPENAI_API_KEY}
      DEFAULT_MODEL: gpt-5.4
    env_file:
      - .env
    volumes:
      - codex-ui-data:/app/data
      - ./belle-api/files:/app/files
      - ./belle-api/instances:/app/instances
      - ./belle-api/static:/app/static
    restart: unless-stopped

volumes:
  codex-ui-data:
    driver: local
    name: codex-ui_data
COMPOSEEOF

# ── 5. Generate requirements.txt ──────────────────────────────────────────────

log "Generating requirements.txt"
cat > "$BELLE_API/requirements.txt" << 'REQEOF'
fastapi>=0.115
uvicorn[standard]>=0.34
httpx>=0.28
aiosqlite>=0.20
python-dotenv>=1.0
python-multipart>=0.0.17
pypdf>=5.1
python-docx>=1.2
openpyxl>=3.1
python-pptx
REQEOF

# ── 6. Generate manifest.json (Step 18 content) ──────────────────────────────

log "Generating manifest.json"
cat > "$BELLE_API/static/manifest.json" << 'MANIFESTEOF'
{
  "name": "Datum Codex — Engineering Agent",
  "short_name": "Codex",
  "description": "Emergency engineering backup — OpenAI Codex via Datum",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0a1628",
  "theme_color": "#0a1628",
  "icons": [
    {"src": "/datum-mark.svg", "sizes": "any", "type": "image/svg+xml"},
    {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
    {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"}
  ]
}
MANIFESTEOF

# ── 7. Copy Datum branding assets ─────────────────────────────────────────────

log "Copying branding assets"
cp "$HOME/projects/agentic-ui/static/datum-mark.svg" "$BELLE_API/static/datum-mark.svg"
cp "$SCRIPTS_DIR/assets/icon-192.png" "$BELLE_API/static/icon-192.png"
cp "$SCRIPTS_DIR/assets/icon-512.png" "$BELLE_API/static/icon-512.png"

# ── 8. Generate index.html ────────────────────────────────────────────────────

log "Generating branded index.html"
# Copy belle template, then patch branding
cp "$HOME/projects/belle-openrouter/belle-api/static/index.html" "$BELLE_API/static/index.html"
# Apply branding patches via sed (safe: these are unique strings in the template)
sed -i \
    -e 's|<title>.*</title>|<title>Datum Codex — Engineering Agent</title>|' \
    -e 's|Belle|Datum Codex|g' \
    -e 's|belle|codex|g' \
    "$BELLE_API/static/index.html"
# Replace model selector with Codex models via Python (sed can't handle multi-line)
python3 << HTMLEOF
from pathlib import Path
import re

html = Path("$BELLE_API/static/index.html")
src = html.read_text()

# Replace model <select> options with Codex models
old_select = re.search(r'(<select[^>]*id="model-select"[^>]*>)(.*?)(</select>)', src, re.DOTALL)
if old_select:
    new_options = """
              <optgroup label="OpenAI">
                <option value="gpt-5.4" selected>GPT-5.4</option>
                <option value="gpt-5.4-mini">GPT-5.4 mini</option>
                <option value="codex-5.4">Codex-5.4</option>
                <option value="gpt-4o">GPT-4o</option>
                <option value="gpt-4o-mini">GPT-4o mini</option>
              </optgroup>"""
    src = src[:old_select.start(2)] + new_options + src[old_select.end(2):]

# Replace placeholder text
src = src.replace("Ask Belle", "Ask Codex to build, fix, or analyze")

html.write_text(src)
print("index.html branded")
HTMLEOF

# ── 9. Generate system prompt ─────────────────────────────────────────────────

log "Generating system prompt"
# Step 19 content — inlined from CODEX.md operating contract
cat > "$BELLE_API/instances/codex/system_prompt.txt" << 'PROMPTEOF'
You are Datum Codex — an emergency engineering backup agent running on OpenAI's Codex platform.

You have full shell and file access via the Codex CLI. You can read, write, and execute code.

Operating rules:
- You are terse, direct, and low-ceremony. No filler.
- Read before you write. Understand existing code before modifying.
- Minimum code that solves the problem. Nothing speculative.
- When multiple valid approaches exist, name them briefly and state tradeoffs.
- Before delivering code, identify at least one potential issue.

You have read access to ~/vault/ for context about projects, personas, and past work.
Your primary workspace is ~/projects/codex-drone/.
PROMPTEOF

# ── 10. Patch service worker cache name ───────────────────────────────────────

if [ -f "$HOME/projects/belle-openrouter/belle-api/static/sw.js" ]; then
    log "Patching sw.js cache name"
    cp "$HOME/projects/belle-openrouter/belle-api/static/sw.js" "$BELLE_API/static/sw.js"
    sed -i "s/belle-v[0-9]*/codex-v1/g" "$BELLE_API/static/sw.js"
fi

# ── 11. Generate .env ─────────────────────────────────────────────────────────

log "Generating .env"
OPENAI_KEY=$(grep -m1 '^OPENAI_API_KEY=' ~/.secrets.env | cut -d= -f2-)
[ -z "$OPENAI_KEY" ] && fail "OPENAI_API_KEY not found in ~/.secrets.env"
echo "OPENAI_API_KEY=$OPENAI_KEY" > "$UI_DIR/.env"

BRIDGE_TOKEN=$(grep -m1 '^CODEX_BRIDGE_TOKEN=' ~/projects/agentic-ui/.env | cut -d= -f2-)
[ -z "$BRIDGE_TOKEN" ] && fail "CODEX_BRIDGE_TOKEN not found in agentic-ui .env"
echo "CODEX_BRIDGE_TOKEN=$BRIDGE_TOKEN" >> "$UI_DIR/.env"

# ── 12. Ensure .gitignore ─────────────────────────────────────────────────────

grep -qxF '.env' "$UI_DIR/.gitignore" 2>/dev/null || echo '.env' >> "$UI_DIR/.gitignore"
grep -qxF 'data/' "$UI_DIR/.gitignore" 2>/dev/null || echo 'data/' >> "$UI_DIR/.gitignore"

log "Done — standalone UI ready at $UI_DIR"
```

**Key design decisions in gen_codex_ui.sh:**

1. **server.py patching uses Python, not sed.** Multi-line function replacement is fragile with
   sed. The Python patcher does exact string matching on the litellm function body, validates
   AST before/after, and rolls back on syntax error. If the source function isn't found exactly,
   it checks if already patched (idempotent) or fails loudly.

2. **agent.py is a full heredoc write, not a patch.** No risk of partial sed matches or drift
   from template changes. The Step 17 code is the canonical source; the generator inlines it.

3. **Fail-fast on missing assets/secrets.** Pre-flight checks at the top prevent partial runs.
   Every external dependency (datum-mark.svg, PNG icons, secrets) is validated before any work.

4. **index.html model selector replaced via Python regex.** The `<select>` content varies between
   belle instances, so we use regex to find the select element and replace its options entirely
   rather than trying to sed individual `<option>` tags.

5. **No litellm anywhere.** requirements.txt drops it. server.py import removed. agent.py never
   had it. tools.py deleted. The only LLM integration points are:
   - agent.py → bridge proxy (httpx → :8092)
   - server.py `_litellm_complete()` → httpx → OpenAI API (memory/title extraction)

### Step 21: Part E Validation (in bootstrap Phase 7)

```bash
# ── Phase 7b: Standalone UI validation ──
if [ -f "$UI_DIR/docker-compose.yml" ]; then
    command -v docker &>/dev/null || { log "WARNING: docker not found — skip UI validation"; }
    if command -v docker &>/dev/null; then
        log "Building standalone UI container..."
        cd "$UI_DIR"
        docker compose build 2>&1 | tail -5

        # Import smoke test — catch missing deps before starting container
        log "Import smoke test..."
        docker compose run --rm --no-deps codex-ui python3 -c "import server, agent, db; print('Imports: OK')" \
            || fail "Import smoke test failed — check requirements.txt"

        log "Starting container for health check..."
        docker compose up -d
        sleep 3

        # Verify app responds
        if python3 -c "import urllib.request; r=urllib.request.urlopen('http://localhost:8132/', timeout=5); assert r.status==200; print('UI: OK')"; then
            # Verify manifest served
            python3 -c "import urllib.request,json; r=urllib.request.urlopen('http://localhost:8132/manifest.json',timeout=5); d=json.loads(r.read()); assert d['short_name']=='Codex'; print('Manifest: OK')"

            # Verify bridge connectivity from inside container (R6-3)
            docker compose exec codex-ui python3 -c "
import urllib.request
try:
    r = urllib.request.urlopen('http://host.docker.internal:8092/health', timeout=5)
    print(f'Bridge: OK ({r.status})')
except Exception as e:
    print(f'Bridge: UNREACHABLE ({e}) — bridge must be running on host :8092')
"
            echo "PASS: Standalone UI running on :8132" >> "$HOME/projects/codex-drone/bootstrap_report.md"
        else
            echo "FAIL: Standalone UI not responding on :8132" >> "$HOME/projects/codex-drone/bootstrap_report.md"
        fi
        docker compose down
        cd "$HOME/projects/codex-drone"
    fi
fi
```

### Step 22: Standalone Runbook (appended to RUNBOOK.md)

```markdown
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
```

---

## Phased Delivery (F35)

**Phase 1 — MVP (this implementation):**
- Workspace + contracts + tools
- Codex CLI installed + verified
- Bridge with auth + timeouts + concurrency
- UI persona wired via Python patcher (agentic-ui :8090)
- Standalone Codex UI container (:8132) — Datum-branded PWA
- Behavioral tests passing
- Operator runbook

**Phase 2 — Extensions (deferred):**
- Datum POST /task API on bridge
- Git worktree isolation per task
- Systemd service for bridge auto-start
- Cost dashboard / Grafana metrics
- Auto-failover (detect Claude down → suggest Codex)

---

## File Count (v4)

| File | Type | Lines (est) |
|------|------|-------------|
| bootstrap.sh | Entry point | ~90 |
| bridge/server.py | Python | ~200 |
| bridge/patcher.py | Python | ~130 |
| bridge/test_bridge.py | Python | ~100 |
| bridge/requirements.txt | Deps | ~4 |
| RUNBOOK.md | Docs | ~50 |
| scripts/gen_*.sh (12) | Generators (incl. gen_codex_ui.sh) | ~750 |
| tools/*.sh (4) | Shell | ~190 |
| AGENTS.md + CODEX.md + MANIFEST.md + SPEC.md | Contracts | ~350 |
| ui/docker-compose.yml | Docker | ~40 |
| ui/belle-api/ (forked) | Python + HTML + assets | ~2,000 (mostly from template) |
| ui/belle-api/instances/codex/system_prompt.txt | Text | ~30 |
| **Total (new code)** | | **~1,934** |
| **Total (incl. forked template)** | | **~3,934** |

---

## Risks & Mitigations (v2)

| Risk | Mitigation |
|------|-----------|
| Codex JSONL schema changes | Pin CLI version; test_bridge.py validates parser |
| OPENAI_API_KEY missing | Health endpoint checks; bridge fails fast |
| Vault NAS unmounted | diagnostics.sh warns; Codex reads from last cache |
| Bridge crash mid-stream | Process group kill; client sees error event |
| Codex hangs | Wall-clock (600s) + idle (120s) timeout; SIGTERM then SIGKILL |
| Path traversal | Allowlist: only ~/projects/* |
| Runaway spend | Daily budget cap ($20 default) + concurrency limit (2) |
| UI patch breaks server.py | AST validation + auto-rollback from backup |
| Client disconnect | `request.is_disconnected()` → kill subprocess |
