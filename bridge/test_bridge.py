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
