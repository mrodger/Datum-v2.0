# Team — OpenCode Migration

**Project owner:** Manager
**Methodology:** Leyline (plan/execute/verify per phase)

---

## Roster

| Persona | Role | Phases owned | Responsibility |
|---|---|---|---|
| **Manager** | Project owner, decision gate | A, F (cutover sign-off), H | Phase reviews, decision capture, GDrive + GitHub sync, escalation |
| **Developer** | Lead engineer | B, C, D, E, F, G | Subprocess swap, MCP port, smoke tests, guardrails, cutover. Owns `~/projects/opencode-ui/` and `~/projects/datum-ui/server.py` |
| **Designer** | Diagrams + UI v3 | Diagrams (now), I (post-June) | Re-render mermaid diagrams in this project as branded SVG/PDF. Owns Phase I (UI v3) post-cutover |
| **Researcher** | Reference + validation | E (model routing review) | Cross-check model routing decisions against research docs. On-call for unknown model behaviour |
| **Security** | Auth + guardrails review | D (review), H (decommission review) | Cost cap + circuit breaker review. Sign off on Phase H rollback procedure |
| **Sysadmin** | Infra + DNS | F | DNS swap (apps.geofabnz.com → vm107), vm102 retirement procedure, NFS contention check |

---

## Communication

- **Daily:** Manager checks task progress and blockers in this folder's `tasks.md`
- **Per phase:** Leyline plan reviewed and signed off before execute begins
- **Handoffs:** Cross-persona notes via `~/vault/shared/handoff.md`
- **Escalation:** Manager → Marcus (direct) for any decision needed outside the 5 documented open questions

---

## Working agreements

1. Phase order is enforced. No starting C until B verify is green.
2. Every phase produces evidence (lite-verify output captured in `phases/<phase>/verify.md`).
3. If a phase misses its window, Manager surfaces it — we do not silently slip.
4. Claude CLI stays installed for 30 days post-Phase H as emergency rollback.
5. No persona except Manager edits this `README.md`. Phase files are owned by the phase's lead.
