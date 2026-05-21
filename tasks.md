# Tasks — OpenCode Migration

**Sort order:** June viability first. Anything Pelorus can self-improve post-cutover is at the bottom.

---

## Phase A — Auth + Drones ✅ DONE 2026-05-21

- [x] Move `~/.secrets.env` source line above interactive guard in vm107 `~/.bashrc`
- [x] Verify `opencode auth list` picks up 4 providers from non-interactive ssh
- [x] Verify drone endpoints `192.168.88.111:3010` and `:3011` reachable
- [x] Update mental model: vm106 decommissioned, drones live on vm111

---

## Phase B — datum-local + Stratum MCP registration 🟡 NEXT

**Owner:** Developer
**Acceptance:** opencode session can call `vault_search`, `dispatch_drone`, `voice_tts` plus at least one Stratum tool without errors.

- [ ] Identify `datum-local` MCP stdio command path on vm107
- [ ] Add `datum-local` block to `~/.config/opencode/opencode.json` under `mcp`
- [ ] Identify Stratum (`datum-mcp` v0.4.0) MCP command path
- [ ] Add Stratum block alongside `datum-local` (decoupled — both registered, no merge)
- [ ] Restart opencode session, verify tool list includes both servers' tools
- [ ] Smoke test: `vault_search "manager tasks"` from opencode CLI
- [ ] Smoke test: `dispatch_drone "test task"` returns taskId
- [ ] Smoke test: `voice_tts "ok"` produces audio file
- [ ] Smoke test: one Stratum tool call (e.g. workspace list or code-library search)
- [ ] Capture surface-overlap notes (datum-local vs Stratum) in `decisions/mcp-coexistence.md`
- [ ] Document any tool conflicts (name collisions) and resolution

---

## Phase C — Persona smoke tests + /handoff

**Owner:** Developer
**Acceptance:** All 24 personas pass; differences documented.

- [ ] Build matrix: 24 personas × {init, /handoff, persona-specific tool}
- [ ] Run `opencode run --agent <persona> "init"` for each
- [ ] Verify startup block renders (persona name, tasks count, MEMORY date, tools, usage)
- [ ] Verify `/handoff --tokens N --notes 'smoke'` writes to correct workspace files
- [ ] Capture divergence from Claude Code into `decisions/persona-smoke.md`
- [ ] Flag any persona that fails for follow-up before Phase D

---

## Phase D — Token + cost guardrails (Batch 1.5 unfrozen)

**Owner:** Developer · **Review:** Security
**Acceptance:** Real cost visible per message. Cap-exceeding tasks terminate cleanly.

- [ ] Parse `step_finish` event in opencode JSON stream for `tokens.{input,output,reasoning,cache}` and `cost`
- [ ] Wire those values into the `done` SSE event emitted by `agent.py`
- [ ] Add per-task token cap (default: 100k input / 20k output)
- [ ] Add per-task USD cap (default: $0.50)
- [ ] Add circuit breaker at 3× estimate
- [ ] Surface cost + tokens in UI status bar (opencode-ui)
- [ ] Test: deliberately blow cap, verify clean termination + clear error
- [ ] Security review of cap + circuit-breaker code

---

## Phase E — Model routing + OpenAI spend cap

**Owner:** Developer · **Review:** Researcher
**Acceptance:** OpenAI cap live, per-persona routing in opencode.json, dry-run ≤ target.

- [ ] Encode per-persona model table from README into `~/.config/opencode/opencode.json` (three tiers: gpt-5.4-nano, gpt-5.4-mini, gpt-5.4)
- [ ] Set OpenAI monthly cap to $80 with 50/80/95% alerts
- [ ] Remove Anthropic + DeepSeek + OpenRouter default routes for personas (OpenRouter retained for MCP optionality + research-drone escalation only)
- [ ] Researcher cross-checks routing against inference research doc
- [ ] Run one-week dry-run with representative workload
- [ ] Capture actuals into `memory.md` and update README cost projection
- [ ] Apply drone DEFAULT_MODEL=gpt-5.4-mini on vm111 drone containers; nano for fan-out tasks

---

## Phase F — server.py cutover (vm102 → Pelorus, 30-day cold standby)

**Owner:** Developer · **Co-owner:** Sysadmin
**Acceptance:** apps.geofabnz.com served from Pelorus; vm102 datum-ui stopped + masked; 30-day archival timer scheduled.

- [ ] Pre-cutover: snapshot vm102 datum-ui.db to `~/vault/projects/opencode-migration/archive/vm102-datum-ui-pre-cutover.db.gz`
- [ ] DNS swap: `apps.geofabnz.com` → vm107:8191
- [ ] `systemctl stop datum-ui` + `systemctl mask datum-ui` on vm102
- [ ] Disable vm102 NFS vault writer (read-only mount or unmount)
- [ ] Verify NFS vault contention resolved (single writer test from Pelorus)
- [ ] Update MEMORY.md: hybrid validation period closed
- [ ] Smoke test: send message via apps.geofabnz.com, verify response from Pelorus
- [ ] Schedule 30-day calendar reminder for vm102 archival decision (2026-06-20)

---

## Phase G — Scheduled jobs + automation

**Owner:** Developer · **Sysadmin** for cron/timer changes
**Acceptance:** No undocumented `claude` invocations in tools/projects/cron paths.

- [ ] Inventory: `grep -rE '\bclaude\b' ~/tools ~/projects/*/cron* ~/projects/*/*.sh`
- [ ] Rewrite `daily_brief.sh` to use opencode
- [ ] Rewrite `schedule` skill if it invokes claude directly
- [ ] Audit drone bootstrap scripts
- [ ] Verify all systemd timers swapped
- [ ] Re-run inventory grep, document any deliberate exclusions

---

## Phase H — Claude CLI decommission

**Owner:** Manager · **Review:** Security
**Acceptance:** Sign-off gate. June 1 internal deadline.

- [ ] Verify all phases A–G are green with evidence captured
- [ ] Write `RUNBOOK.md` covering rollback procedure (re-enable claude CLI)
- [ ] Security review of rollback procedure
- [ ] Mark `claude` CLI as decommissioned in production path
- [ ] Keep installed for 30 days as emergency rollback
- [ ] Phase H verify → project enters maintenance mode

---

## Phase I — UI v3 (post-cutover polish)

**Owner:** Designer · **Deferred until Batch 3 closes.**

Sourced from `~/vault/research/datum-ui-design-2026.md`. Lower priority than June viability.

- [ ] PWA fundamentals (manifest, service worker, install prompt)
- [ ] Artifact pane refresh (Monaco, MapLibre, AG Grid)
- [ ] Multi-agent orchestration UI (drone fleet visibility, cost/turn dashboard)
- [ ] Design system polish (Vercel/Linear/Raycast/Cursor reference)
- [ ] 3D thought viewer for long-running drone tasks

---

## Phase J — Mymir phase F (claim extraction)

**Owner:** Developer · **Deferred until Batch 3 closes.**

Resume Batch 2. memory.* schema populated; claims/episodes/procedures empty.

- [ ] Scope: LLM model choice for extraction
- [ ] Scope: batch size
- [ ] Scope: retention policy
- [ ] Build extraction pipeline → `memory.claims` + `claim_mentions` + `claim_embeddings`
- [ ] HNSW dedup index
- [ ] Backfill historical messages

---

## Cross-cutting / outside critical path

- [ ] **Designer:** re-render mermaid diagrams in this project as branded SVG/PDF (see handoff.md)
- [ ] **Manager:** answer 5 open questions in README before Phase B closes
- [ ] **Manager:** GDrive sync this folder to `~/gdrive/Datum OpenCode Migration/`
- [ ] **Manager:** push spec to `mrodger/Datum-v2.0` (branch TBD per open question 1)

---

## Done (project-level)

- [x] Identify project scope under "Opencode upgrade and migration" umbrella
- [x] Search GDrive + vault for prior research (8 docs found)
- [x] Create `~/vault/projects/opencode-migration/` folder structure
- [x] Write README.md (spec with mermaid diagrams)
- [x] Write EXECUTIVE_SUMMARY.md
- [x] Write team.md
- [x] Write tasks.md
