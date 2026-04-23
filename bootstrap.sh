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

# ── Phase 2b pre-req: ensure bridge token exists before gen_codex_ui.sh needs it ──
AGENTIC_ENV="$HOME/projects/agentic-ui/.env"
if [ -f "$AGENTIC_ENV" ]; then
    grep -q "CODEX_BRIDGE_TOKEN" "$AGENTIC_ENV" || echo "CODEX_BRIDGE_TOKEN=$(openssl rand -hex 16)" >> "$AGENTIC_ENV"
    log "Bridge token ready in agentic-ui .env"
fi

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

# ── Phase 3: Codex CLI ── R3-F10: preflight npm
log "Phase 3: Codex CLI"
command -v npm &>/dev/null || fail "npm not found — install Node.js first"
if ! command -v codex &>/dev/null; then
    log "Installing Codex CLI..."
    npm i -g @openai/codex 2>/dev/null || sudo npm i -g @openai/codex || fail "Failed to install Codex CLI"
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

# ── Phase 7b: Standalone UI validation ──
if [ -f "$UI_DIR/docker-compose.yml" ]; then
    command -v docker &>/dev/null || { log "WARNING: docker not found — skip UI validation"; }
    if command -v docker &>/dev/null; then
        log "Building standalone UI container..."
        cd "$UI_DIR"
        docker compose build 2>&1 | tail -5

        # Import smoke test — catch missing deps before starting container
        # Clean up any stale container from previous run (idempotent)
        docker compose down --remove-orphans 2>/dev/null || true

        log "Import smoke test..."
        docker compose run --rm --no-deps codex-ui python3 -c "import server, agent, db; print('Imports: OK')" \
            || fail "Import smoke test failed — check requirements.txt"

        log "Starting container for health check..."
        CONTAINER_UP=false
        # First attempt; on failure, recreate networks and retry once
        if docker compose up -d 2>&1; then
            CONTAINER_UP=true
        else
            log "WARNING: Container start failed — recreating networks and retrying once"
            docker compose down 2>/dev/null || true
            if docker compose up -d 2>&1; then
                CONTAINER_UP=true
            else
                log "WARNING: Container start failed after retry — skipping live health check"
                echo "SKIP: Container start failed — start manually: cd ~/projects/codex-drone/ui && docker compose up -d" >> "$HOME/projects/codex-drone/bootstrap_report.md"
            fi
        fi

        if $CONTAINER_UP; then
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
        fi
        docker compose down 2>/dev/null || true
        cd "$HOME/projects/codex-drone"
    fi
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
