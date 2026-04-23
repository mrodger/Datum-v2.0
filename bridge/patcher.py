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
