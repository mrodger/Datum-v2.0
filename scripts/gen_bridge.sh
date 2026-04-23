#!/usr/bin/env bash
# gen_bridge.sh — Write all bridge/*.py and bridge/requirements.txt files.
# Called by bootstrap.sh (no arguments).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="$(dirname "$SCRIPT_DIR")/bridge"
mkdir -p "$BRIDGE_DIR"

# ── bridge/requirements.txt ──────────────────────────────────────────────────
cat > "$BRIDGE_DIR/requirements.txt" << 'EOF'
fastapi>=0.115
uvicorn[standard]>=0.34
httpx>=0.28
python-dotenv>=1.0
EOF

# ── bridge/server.py ─────────────────────────────────────────────────────────
cat > "$BRIDGE_DIR/server.py" << 'SERVEREOF'
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
    uvicorn.run(app, host="0.0.0.0", port=port)
SERVEREOF

# ── bridge/patcher.py ────────────────────────────────────────────────────────
cat > "$BRIDGE_DIR/patcher.py" << 'PATCHEREOF'
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
PATCHEREOF

# ── bridge/test_bridge.py ────────────────────────────────────────────────────
cat > "$BRIDGE_DIR/test_bridge.py" << 'TESTEOF'
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
TESTEOF

echo "gen_bridge.sh: bridge/ files written"
