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
"""Patch belle server.py to remove litellm dependency."""
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
        raise SystemExit("FAIL: Cannot find _litellm_complete to patch — server.py may have changed")
else:
    src = src.replace(old_func, new_func)

# Health endpoint patches
src = src.replace('"belle-assistant"', '"datum-codex"')
src = src.replace('"litellm"', '"codex-bridge"')

# Replace DEFAULT_MODEL reference in health endpoint with a string literal
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

# ── 4. Generate docker-compose.yml ────────────────────────────────────────────

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

# ── 6. Generate manifest.json ─────────────────────────────────────────────────

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
src = src.replace("Ask Codex", "Ask Codex to build, fix, or analyze")

html.write_text(src)
print("index.html branded")
HTMLEOF

# ── 9. Generate system prompt ─────────────────────────────────────────────────

log "Generating system prompt"
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
