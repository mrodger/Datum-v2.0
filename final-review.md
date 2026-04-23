# Final Review — Codex Drone Plan v3

**Reviewer:** GPT-5.4 (Drone task bff28da3)
**Verdict:** REJECT
**Cost:** $0.055 | **Duration:** 59.2s | **Turns:** 1

## Correctly Fixed (5/7)
- C1: run_codex_agent try/except — FIXED
- C3: Guaranteed done event — FIXED
- H1: Minimal subprocess env — FIXED
- H2: httpx timeout match — FIXED
- H4: httpx import guard — FIXED

## Partially Fixed (2/7)
- C2: Frontend patching fragile (string replace, idempotence heuristic)
- H3: .env not created if absent, bridge doesn't load .env, runbook gap

## New Findings (12)

### Blocking (must fix)
1. project_dir not wired from UI/server to bridge — always falls to default workspace
2. Bridge not started during bootstrap tests — health check test will fail
3. Bridge server doesn't load .env — CODEX_BRIDGE_TOKEN missing at runtime
4. pip install || true swallows failures silently
5. Git commit (Phase 6) before validation (Phase 7-8) — captures broken state

### Important (should fix)
6. verify_auth() written like FastAPI dependency but called manually
7. Health check hardcodes vault/dev path
8. JSONL parser assumes flat strings (may be nested content blocks)
9. No E2E test proving streamed events render correctly in UI
10. Bootstrap doesn't check npm exists before codex install

### Noted (acceptable for MVP)
11. Regex patching still brittle (acknowledged, deferred)
12. Profile/sandbox precedence ambiguity (--full-auto vs profile)

---

# Round 4 Re-review — After Fixes

**Reviewer:** GPT-5.4 (Drone task f41f4e0c)
**Verdict:** APPROVE
**Cost:** $0.028 | **Duration:** 9.8s | **Turns:** 1

## Blocking Fix Verification (5/5 passed)
1. project_dir strategy — FIXED (documented workspace model, consistent with agentic-ui pattern)
2. bridge .env loading — FIXED (python-dotenv, loads both bridge/.env and project .env)
3. bootstrap test sequencing — FIXED (offline first, start bridge, live tests, kill bridge)
4. pip install error handling — FIXED (hard-fail on error, no || true)
5. git commit ordering — FIXED (Phase 8, after validation)

## Remaining blocking issues: NONE
## Final verdict: APPROVE

---

# Part E Reviews — Standalone Codex UI

## Round 5: Part E Initial Review (task a38e6e92)
**Verdict:** REJECT | **Cost:** $0.043 | **Duration:** 44.6s
**Gaps found:** 6
1. Dockerfile location inconsistency (ui/ vs ui/belle-api/)
2. agent.py handling unclear (copy vs generate)
3. Missing Part E bootstrap validation (docker build + health)
4. Icon generation depends on rsvg-convert at runtime
5. LiteLLM model routing for gpt-5.4 unverified
6. No standalone runbook entries

## Round 6: Part E Re-review (task 86080fb2)
**Verdict:** APPROVE | **Cost:** $0.036 | **Duration:** 13.1s
All 6 gaps verified fixed. Plan is implementation-ready.

---

# Full Review History

| Round | Task | Reviewer | Scope | Verdict | Cost |
|-------|------|----------|-------|---------|------|
| R1 | 80da8fcb | GPT-5.4 adversarial | Full plan | REJECT (36 findings) | $0.10 |
| R2 | 027b0e3c | GPT-5.4 architect | Full plan v2 | APPROVE_WITH_CONDITIONS (9) | $0.06 |
| R3 | — | Claude Opus 4.6 | Integration review | 7 findings (all fixed) | — |
| R4a | bff28da3 | GPT-5.4 architect | Full plan v2+ | REJECT (12 findings) | $0.05 |
| R4b | f41f4e0c | GPT-5.4 architect | Blocking fixes | APPROVE | $0.03 |
| R5 | a38e6e92 | GPT-5.4 architect | Part E only | REJECT (6 gaps) | $0.04 |
| R6 | 86080fb2 | GPT-5.4 architect | Part E fixes | APPROVE | $0.04 |
| **Total** | | | | | **$0.36** |

---

### Round 6: GPT-5.4 Part E v4 Bridge Proxy Review (task 816eb53d)

**Verdict:** APPROVE_WITH_CONDITIONS (6 condition groups — all addressed in v4)
**Model:** GPT-5.4
**Date:** 2026-04-23

**Conditions (all resolved):**
1. server.py import compatibility — verified
2. Event schema + history dedup + OpenAI API compat + asset existence + rm safety — all fixed
3. Docker networking + bridge bind docs — documented + validation added
4. Dependency completeness (python-multipart) — added to requirements.txt
5. Security (.env gitignore, bridge exposure, shared token, no UI auth) — documented
6. Bootstrap idempotency (rm -rf, .env parsing, patch markers) — hardened

