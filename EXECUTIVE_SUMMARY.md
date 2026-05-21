# Executive Summary — OpenCode Migration

**Date:** 2026-05-21
**Owner:** Manager
**Decision needed by:** 2026-05-24 (Phase B kickoff)
**Hard deadline:** 2026-06-01 (Anthropic OAuth retirement)

---

## The forcing function

Anthropic is moving all `claude -p` (Claude Code OAuth) usage to API billing in June. Datum runs `claude` CLI as a subprocess in every persona surface, every drone, and every scheduled job. After June 1 every one of those invocations becomes a metered API call. At current footprint that is multiples of $100/month for work that OpenRouter-routed OpenCode can do for **$35–$65/month** with prompt caching applied.

We have ten days to ship a platform-wide cutover.

---

## The plan in one paragraph

Pelorus (vm107) is already running OpenCode 1.14.50 with 24 persona agents and 41 commands. Auth was fixed today (Phase A). The remaining work is: port the `datum-local` MCP surface across so OpenCode personas have vault/drone/voice parity, walk all 24 personas through a smoke test, wire real token + cost capture (the Batch 1.5 work that was deferred — now blocking), set per-persona model routing with an OpenRouter spend cap, retire vm102's `datum-ui` in favour of Pelorus's `opencode-ui`, swap the remaining cron/timer jobs, then decommission the `claude` CLI. Eight phases (B–H), each one a Leyline plan/execute/verify cycle.

---

## What is in scope

- Subprocess swap: `claude --output-format stream-json` → `opencode run --format json`
- MCP parity (vault search, drone dispatch, voice, conversation CRUD)
- Per-persona model routing with cost guardrails
- vm102 → Pelorus cutover, with NFS vault contention resolved as a side effect
- Cron/timer/scheduled-job rewrites

## What is out of scope (deferred to Phase I/J post-June)

- UI v3 (PWA, artifact pane refresh, multi-agent UI)
- Mymir phase F (claim extraction pipeline)
- Batch 2 sub-plans 3+

**Rule:** if Pelorus can build it for itself once viable, it is lower priority than what makes Pelorus viable in the first place.

---

## Cost case

| | Pre-migration (June API billing) | Post-migration (OpenCode + OpenAI direct) |
|---|---|---|
| Monthly direct API spend | ~$100–$300 (estimate) | **$25–$50** |
| OpenAI spend cap | n/a | $80/month (alert 50/80/95%) |
| Provider strategy | Anthropic OAuth | OpenAI direct only (gpt-5.4 nano/mini/full) |
| Drone fleet | unmetered (Claude Code) | gpt-5.4-mini default, gpt-5.4-nano for fan-out/status |

Phase D + E numbers will replace these estimates with actuals from a one-week dry-run.

---

## Risk profile

| Risk | Mitigation |
|---|---|
| OpenAI outage | Phase H rollback to Claude CLI (kept installed 30 days post-decom). OpenRouter remains available for MCP optionality |
| Persona behaviour drift on non-Claude models | Phase C smoke tests with documented diffs; researcher persona on gpt-5.4 (most capable tier) for highest-stakes work |
| Cost spike from runaway agent | Phase D guardrails + OpenAI spend cap |
| MCP regression | Phase B per-tool acceptance test |
| Schedule slippage past June 1 | Phase H is hard gate; rollback to Claude Code BYOK if any phase misses |

---

## Acceptance gates (8)

1. No `claude` CLI calls in production path
2. `opencode` runs cleanly from any non-interactive ssh
3. 24 personas pass smoke test
4. All datum-local MCP tools accessible from OpenCode
5. Token + cost ceilings live and visible
6. Per-persona model routing in `opencode.json`
7. One-week measured spend ≤30% of Claude-Code-equivalent
8. `apps.geofabnz.com` served from Pelorus

---

## Decisions resolved 2026-05-21

1. **GitHub layout.** New branch `opencode-migration` on `mrodger/Datum-v2.0`.
2. **vm102 retirement.** Cold standby for 30 days, then archive.
3. **Provider strategy.** OpenAI direct only (gpt-5.4 nano / mini / full). No Anthropic BYOK in Batch 3.
4. **Drone routing.** Default `gpt-5.4-mini`; nano for fan-out and status; full for research-drone escalation.
5. **Stratum coupling.** Decoupled for Batch 3 — register Stratum MCP alongside `datum-local`. Consolidation deferred to Batch 4.

---

## Recommendation

Approve Phase B (datum-local MCP port) and Phase C (persona smoke tests) for immediate start. These two unblock everything else and produce evidence that the rest of the plan is real before any irreversible cutover work happens.
