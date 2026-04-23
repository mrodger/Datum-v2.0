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
