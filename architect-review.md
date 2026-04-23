# Solutions Architect Review — Codex Drone Plan v2

**Reviewer:** GPT-5.4 (Drone task 027b0e3c)
**Verdict:** APPROVE_WITH_CONDITIONS
**Cost:** $0.063 | **Duration:** 51.6s | **Turns:** 2

---

## Verdict Summary

Strong emergency-use MVP. Clear step up from the rejected v1. Likely works in a controlled
local deployment. Architecture is directionally appropriate for Datum as a fallback agent.

9 conditions for production approval listed below.

## Conditions for Production Approval

1. **Capture real Codex JSONL fixtures** — pinned CLI version, update parser/tests against real payloads
2. **End-to-end UI integration tests** — prove SSE renders correctly for success, error, timeout, cancellation
3. **Demonstrate sandbox enforcement empirically** — workspace, inbox, curated, vault write tests
4. **Replace regex patching with stable integration point** — or pin agentic-ui version + test in CI
5. **Define real deployment model** — systemd/container, pinned deps, restart policy, env management, logs
6. **Persist budget and audit records** — outside process memory
7. **Emit distinct terminal statuses** — not generic "done" for timeout/cancel/error
8. **Resolve subprocess env policy** — implementation must match stated minimal-env design
9. **Constrain initial production scope** — single host, documented repo/workspace boundaries

## Key Findings by Area

### Integration Correctness
- Bridge pattern is appropriate
- Auth, workspace allowlisting, subprocess lifecycle all correct
- **Risk:** SSE/event translation still assumes Codex payload shapes without captured fixtures
- **Risk:** Possible duplicate text if both item.started deltas and item.completed content emitted
- **Risk:** Terminal states conflated (timeout vs cancel vs error all → generic done)

### Operational Readiness
- RUNBOOK, health endpoint, structured logging, spend limits — all good
- **Gap:** No service management (systemd/container deferred)
- **Gap:** Dependency installation too loose (no venv, no version pins)
- **Gap:** Budget tracking in-memory only (resets on restart)
- **Gap:** No observability beyond stdout

### Architecture Fitness
- Fits Datum as emergency local fallback
- Persona-based routing correct
- Vault read / inbox write model aligns with Datum memory concepts
- **Mismatch:** Bootstrap-centric sidecar, not first-class Datum subsystem
- **Mismatch:** Chat-first task ingestion (no structured handoff/resumability)
- **Mismatch:** STATUS.md heartbeat format unspecified

### Why Not REJECT
Plan addresses biggest earlier failures: auth, process cleanup, timeouts, cost controls,
path allowlisting, tests, runbook, verified CLI contract. Credible MVP design.

### Why Not Full APPROVE
Too many production-critical assumptions remain unproven: exact Codex event payloads,
agentic-ui SSE contract, sandbox enforcement with symlinks, operational deployment model,
persistent controls/audit, brittle UI patching.
