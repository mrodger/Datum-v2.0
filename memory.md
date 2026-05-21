# Project Memory — OpenCode Migration

Living record of architectural decisions, infrastructure state, costs, and known issues.

---

## Architectural decisions

### D1 — Subprocess pattern preserved
OpenCode is wrapped the same way Claude Code is: `agent.py` spawns the CLI with `--format json`, reads the event stream, emits SSE to the UI. We keep the FastAPI + vanilla JS + SSE topology — only the subprocess command changes. Rationale: minimum migration delta, biggest reuse.

### D2 — Pelorus (vm107) is the production orchestrator, vm102 retires
vm107 already runs opencode 1.14.50 with 24 agents and 41 commands. vm102 runs the older datum-ui. Phase F cuts DNS over. Rationale: parallel divergence is already happening (both databases at ~15k messages with separate writes), and NFS vault has write contention as long as both run. Picking a winner stops the bleed.

### D3 — Per-persona model routing (revised 2026-05-21)
Single-vendor strategy for Batch 3: OpenAI direct, three tiers (`gpt-5.4-nano`, `gpt-5.4-mini`, `gpt-5.4`). Developer/Manager/Security/Researcher on full. Routine personas on mini. Fan-out and status on nano. Drones default to mini, escalate to full on research tasks. Captured in README Phase E table. Anthropic BYOK and DeepSeek dropped — re-introduce in Phase I+ if Sonnet 4.6 is missed on coding-heavy work. Rationale: one bill, one cap, predictable caching, simpler Phase D guardrails.

### D4 — Cost guardrails before any cutover (Phase D unfrozen)
Batch 1.5 (token capture + per-task caps) was deferred. Without it, we cannot ship Phase F safely because we have no per-task spend visibility. Phase D is now blocking. Real token counts come from opencode's `step_finish` event.

### D5 — datum-local MCP is the only stdio MCP we port ourselves
External MCPs (tavily, github, gworkspace, brave) already work on opencode. datum-local (vault/drone/voice/conversation CRUD) is the Datum-internal one and the biggest functional gap. Phase B is the port.

### D6 — Mymir phase F (claim extraction) does not block Batch 3
Batch 2 sub-plan 2 phase F is real work but compounds risk with the migration. Defer to Phase J post-cutover. Phase E (data through memory schema) is already done — we are not losing data.

### D7 — Leyline planning per phase
Each phase gets its own `plan.md`, `execute.md`, `verify.md`. No phase ships without verify evidence. Rationale: project history shows that "approximately done" tends to surface as a regression three weeks later.

### D8 — Living document, GDrive mirror, GitHub repo
This folder is the source of truth. GDrive is the share/archive surface. GitHub (mrodger/Datum-v2.0) hosts the spec for external visibility. Open question on which branch.

---

## Infrastructure state (snapshot 2026-05-21)

### vm107 (Pelorus) — production orchestrator
- opencode 1.14.50
- 24 persona agents at `~/.config/opencode/agents/`
- 41 commands at `~/.config/opencode/commands/`
- MCPs configured: tavily, github, google-workspace, brave-search, agent-manager
- MCPs missing: **datum-local (Phase B target)**
- opencode-ui container on Sysbox, port 8191
- Auth: 4 providers (OpenAI, OpenRouter, GitHub Models, GitHub Copilot) via `~/.secrets.env`
- ✅ Auth fix landed 2026-05-21 (bashrc reordering)
- Drone reachability: ✅ vm111:3010 (general, ×3 concurrent) + vm111:3011 (research, ×1 concurrent)

### vm102 — legacy orchestrator
- datum-ui at port 8190 (claude subprocess)
- mymir-db-1 container at port 5432 (ParadeDB latest-pg17)
- Database `mymir`, schema `memory.*` — 14 tables, 35 indexes, 2 HNSW indexes
- memory.messages: 15,314 · memory.conversations: 255 · memory.agents: 15
- memory.claims/episodes/procedures: empty (Phase J)

### vm111 — drone fleet
- :3010 general drone (concurrency 3)
- :3011 research drone (concurrency 1)
- DRONE_URL_LOCAL and DRONE_URL_RESEARCH env vars set in ~/.secrets.env
- ~/tools/drone.py uses DRONE_URL_LOCAL

### vm106 — DECOMMISSIONED
The 2026-05-14 handoff note "vm106 unreachable" is stale. Drones moved off vm106 on 2026-05-16. Treat vm106 as off.

---

## Cost breakdown (estimates pending Phase E dry-run)

| Component | Estimate $/month | Source |
|---|---|---|
| OpenAI gpt-5.4 (developer/manager/security/researcher) | $15–25 | conservative full-tier usage |
| OpenAI gpt-5.4-mini (routine personas + drone default) | $8–18 | bulk |
| OpenAI gpt-5.4-nano (status, fan-out, lookups) | $2–7 | high-volume / low-cost |
| OpenRouter (MCP optionality, research bursts only) | <$2 | throttled |
| **Total target** | **$25–$50** | post-cache |

OpenAI spend cap: **$80/month** with alerts at 50/80/95%.

Pre-migration estimate under June API billing: $100–$300/month (unknown). The case for migration is ≥2× monthly savings before counting cap insurance.

---

## Known issues (carry-forward)

### KI-1 — NFS vault write contention
Two writers (vm102 datum-ui + vm107 opencode-ui) on the same NFS-mounted vault. Already observed as occasional file locking glitches. Resolves at Phase F (single writer).

### KI-2 — agent.py cost_usd hardcoded to 0
`~/projects/opencode-ui/agent.py` returns `cost_usd=0, input_tokens=0, output_tokens=0`. Wired in Phase D.

### KI-3 — GitHub repo content drift
`mrodger/Datum-v2.0` `main` branch is a Codex Drone implementation. `datum-v2-main` branch is a Next.js scaffold with drizzle. MEMORY.md claims the latter is the Mymir fork — contents don't match. **Open question 1 covers this.**

### KI-4 — Stratum MCP surface not reviewed under OpenCode
Stratum has its own MCP surface (datum-mcp v0.4.0, 16 tools, 26 prompts). Whether it needs OpenCode-side review is **open question 5**.

### KI-5 — Drone DEFAULT_MODEL
Currently set to `openrouter/free` on the drone containers. Cheap but unreliable. Phase E open question 4 — upgrade or keep.

### KI-6 — Documentation drift on developer tasks
Developer workspace `tasks.md` still shows Mymir fork tasks as unchecked even though phases A–E are closed (per MEMORY.md). Not blocking but should be reconciled.

---

## Reference docs (vault)

- `~/vault/research/opencode-migration-2026.md` — 6-phase migration playbook (primary)
- `~/vault/research/datum-opencode-inference-stack-2026.md` — provider/model pricing
- `~/vault/research/datum-opencode-mcp-containers-2026.md` — MCP + container security
- `~/vault/research/datum-cost-optimization-2026.md` — routing + caching + drone fleet cost
- `~/vault/research/opencode-memory-injection-2026.md` — memory file injection patterns
- `~/vault/research/datum-ui-design-2026.md` — UI v3 (Phase I)
- `~/vault/research/datum-postgres-memory-2026.md` — Batch 2 (Phase J)
- `~/vault/research/datum-implementation-batches-2026.md` — prior batch grouping (superseded for Batch 3)

## GDrive

- `~/gdrive/Datum OpenCode Migration/` — mirror target (created on first sync)
- Source docs already in `~/gdrive/`: opencode-migration-2026.{docx,pdf}, datum-opencode-inference-stack-2026.{docx,pdf}, datum-opencode-mcp-containers-2026.{docx,pdf}, datum-ui-design-2026.{docx,pdf}, opencode-memory-injection-2026.{docx,pdf}

---

## Change log

- 2026-05-21 — Project created. Phase A done. Spec drafted.
- 2026-05-21 — All 5 open questions resolved. GitHub: new branch `opencode-migration` on Datum-v2.0. vm102: cold standby 30 days. Provider: OpenAI direct only (5.4 nano/mini/full). Drone default: gpt-5.4-mini. Stratum MCP: decoupled for Batch 3, consolidation deferred. Cost target tightened to $25–$50/month.
