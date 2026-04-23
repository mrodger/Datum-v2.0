# Adversarial Review of Codex Drone Bootstrap Specification

## 1. ARCHITECTURE

### Finding 1: The bridge subprocess streaming model has no lifecycle control
**Severity:** CRITICAL

**Problem:**
Each `/chat` request spawns a fresh `codex exec` subprocess with no concurrency limits, no timeout enforcement, no cancellation handling, no backpressure handling, and no cleanup path when the client disconnects. If agentic-ui drops the connection, the subprocess can continue running in the background until completion or hang indefinitely. Repeated requests can pile up into orphaned Codex processes consuming CPU, RAM, file handles, and API spend.

**Fix / mitigation:**
- Track each subprocess per request.
- Detect client disconnect and terminate the child process.
- Apply hard wall-clock timeouts and idle-output timeouts.
- Bound concurrent executions with a semaphore or work queue.
- Add process group management so child tool processes are killed too.

---

### Finding 2: SSE framing is naïve and likely broken under real Codex output
**Severity:** HIGH

**Problem:**
The bridge assumes each stdout line is a complete JSON object and maps it directly to SSE `data:` lines. That only works if Codex JSONL is exactly one JSON object per line and never emits multiline payloads or progress output with embedded newlines. If the CLI changes format or emits structured content spanning lines, the parser silently degrades into garbage text chunks. There is also no event ID, no retry hint, and no explicit completion state reconciliation.

**Fix / mitigation:**
- Confirm and pin to an actual documented machine-readable CLI output contract.
- Implement strict JSONL parsing with schema validation.
- Buffer partial lines and reject malformed events explicitly.
- Add explicit SSE event types and terminal-state tracking.
- Version-gate the bridge to known Codex CLI versions.

---

### Finding 3: Prompt construction is lossy and semantically broken
**Severity:** HIGH

**Problem:**
The bridge only extracts the last user message plus truncated prior messages. It discards system prompts, assistant replies beyond a crude summary, attachments, tool outputs, and any role metadata agentic-ui may rely on. This is not conversation continuation; it is prompt flattening with arbitrary truncation. It will produce inconsistent behavior and hidden regressions.

**Fix / mitigation:**
- Define a canonical conversation-to-prompt transformation.
- Preserve system/developer instructions separately from user text.
- Bound context by tokens, not characters.
- Serialize prior assistant/tool messages explicitly.
- Add tests for multi-turn conversations.

---

### Finding 4: Working-directory selection is unsafe and under-specified
**Severity:** HIGH

**Problem:**
`project_dir` or `workspace` from request body is passed directly to `-C` with no allowlist, no path normalization, no existence check, and no restriction to approved roots. Any caller able to hit the bridge can point Codex at arbitrary host paths. That is effectively remote code execution over the host filesystem.

**Fix / mitigation:**
- Restrict execution to an allowlist of project roots.
- Resolve and validate canonical paths before use.
- Reject symlink traversal outside approved roots.
- Require authentication on the bridge.

---

## 2. SECURITY

### Finding 5: The design explicitly grants broad RW access to the vault and projects with almost no containment
**Severity:** CRITICAL

**Problem:**
This is not a backup engineering agent; it is a host-level automation endpoint with write access to `~/vault`, `~/projects`, and potentially anything reachable from them. The spec says “full vault access” and mounts the vault RW into the bridge runtime while also allowing Codex to run arbitrary shell commands. A prompt injection or accidental bad task can modify long-term memory, project sources, scripts, or any linked path.

**Fix / mitigation:**
- Make vault access read-only by default.
- Separate memory write path from curated knowledge path.
- Restrict project write access to the selected target repo only.
- Use OS-level isolation beyond “workspace-write” assumptions.
- Require an explicit elevated mode for any vault writes.

---

### Finding 6: Secret handling policy is performative, not enforceable
**Severity:** CRITICAL

**Problem:**
The spec says “NEVER read or display `~/.secrets.env`” while simultaneously giving the agent shell access on the host and mounting the file into Docker. That instruction is not a security control. The agent can still read the file directly, source it, print env vars, exfiltrate secrets through tool outputs, or leak them into logs. Environment variables passed to subprocesses are also visible to anything with process inspection privileges.

**Fix / mitigation:**
- Do not mount `~/.secrets.env` into a container that runs untrusted automation.
- Inject only the specific required environment variables.
- Use a credential broker or restricted runtime secret store.
- Add stdout/stderr secret redaction before streaming to clients.
- Stop pretending prompt instructions enforce secret boundaries.

---

### Finding 7: The bridge is an unauthenticated local RCE service
**Severity:** CRITICAL

**Problem:**
`POST /chat` on localhost spawns arbitrary Codex executions against arbitrary directories. There is no authentication, authorization, CSRF protection, request signing, rate limiting, or caller validation. If any local service, browser exploit, extension, or SSRF path can reach localhost, the machine is exposed.

**Fix / mitigation:**
- Require a shared secret or mTLS between agentic-ui and the bridge.
- Bind to a Unix domain socket or loopback with token auth.
- Rate limit and audit all requests.
- Restrict accepted request origins and callers.

---

### Finding 8: Symlink-based trust boundary is unsafe
**Severity:** HIGH

**Problem:**
The plan relies on symlinks (`vault/`, `memory/curated/`) to grant access. Symlinks are not containment. If downstream scripts recurse through them or if path assumptions are wrong, tooling can unexpectedly operate on the real vault. There is no mention of symlink resolution safety in verification or tooling.

**Fix / mitigation:**
- Treat symlinked paths as privileged mounts and guard operations accordingly.
- Use bind mounts or explicit configured paths instead of magical symlink shortcuts.
- Add checks in tools to avoid recursive destructive operations across symlink boundaries.

---

## 3. RELIABILITY

### Finding 9: No handling for bridge crash or restart mid-stream
**Severity:** HIGH

**Problem:**
If the FastAPI process crashes mid-response, agentic-ui gets a broken stream and the Codex subprocess may continue running detached or die unpredictably. There is no task persistence, no resumability, no status recovery, and no terminal-state handoff.

**Fix / mitigation:**
- Introduce a task registry with persisted task state.
- Assign request/task IDs and write status transitions to disk.
- On startup, reconcile orphaned subprocesses or mark tasks failed.
- Distinguish interactive chat from background task execution.

---

### Finding 10: No timeout strategy for Codex hangs or tool deadlocks
**Severity:** HIGH

**Problem:**
The spec assumes Codex returns. It does not address hung subprocesses, stuck tool calls, blocked network operations, or commands waiting on stdin. `httpx` timeout in agentic-ui is not a process timeout; it just governs the client side.

**Fix / mitigation:**
- Add server-side execution timeout and idle timeout.
- Kill the entire process tree on timeout.
- Emit structured timeout errors to the UI.
- Add watchdog metrics.

---

### Finding 11: Partial writes and repo corruption are ignored
**Severity:** HIGH

**Problem:**
If Codex is killed mid-edit, files may be left partially updated, generated artifacts half-written, or repos in broken states. The spec talks about “minimal changes” and “test before done” but says nothing about transactional writes, backups, or rollback strategy.

**Fix / mitigation:**
- Run tasks in a git worktree or temporary branch.
- Auto-stage diffs and write checkpoints.
- Use atomic file replacement in generator scripts.
- Refuse to modify dirty repos without an explicit flag.

---

### Finding 12: Memory inbox/archive workflow has no consistency model
**Severity:** MEDIUM

**Problem:**
The spec says Codex writes to `memory/inbox/` and supervisor promotes later, but there is no naming convention, file locking, conflict handling, retention policy, or cleanup strategy. Parallel tasks can clobber each other or create unreviewable junk.

**Fix / mitigation:**
- Use timestamped/task-scoped directories.
- Define atomic write patterns.
- Add retention and promotion rules.
- Store metadata alongside memory artifacts.

---

## 4. CODEX CLI ASSUMPTIONS

### Finding 13: The spec treats unverified CLI flags and event schemas as facts
**Severity:** CRITICAL

**Problem:**
`codex exec`, `--profile`, `--json`, `-C`, and the exact JSONL methods (`agent/message`, `item/toolCall`, `turn/completed`, etc.) are all presented as if confirmed. There is no evidence they exist in the installed CLI version. This entire bridge depends on those assumptions being correct. If any one of them is wrong, the architecture collapses.

**Fix / mitigation:**
- Verify the actual CLI interface from the installed binary, not memory.
- Capture real sample output and write the parser against that.
- Pin the CLI version.
- Make bootstrap fail fast if the expected commands/flags/schema are absent.

---

### Finding 14: The config model/profile assumptions may not map to real Codex CLI behavior
**Severity:** HIGH

**Problem:**
The plan assumes `.codex/config.toml` is auto-discovered, that these exact profile names are valid, and that approval policy / sandbox settings can be fully controlled this way. If discovery rules differ or the CLI ignores fields, the execution model becomes unpredictable.

**Fix / mitigation:**
- Confirm config file discovery behavior and supported keys.
- Add a smoke test that checks the active profile and effective settings.
- Document fallback behavior if config loading fails.

---

### Finding 15: Headless auth assumptions are risky
**Severity:** MEDIUM

**Problem:**
The spec states no `codex login` is needed and that `OPENAI_API_KEY` “already” exists in environment. That is an environmental assumption, not a system guarantee. In practice, service managers, Docker, and UI-launched processes often do not inherit login-shell environment.

**Fix / mitigation:**
- Explicitly load required env for the bridge process.
- Add startup validation with a hard fail and clear error.
- Do not assume shell profile inheritance.

---

## 5. UI INTEGRATION

### Finding 16: `wire_ui.sh` uses brittle `sed` patching against non-stable source text
**Severity:** HIGH

**Problem:**
The patcher searches for exact lines like `"openai": "OpenAI"` and `use_openai_agent = `. If the target file formatting, quoting, spacing, ordering, or surrounding logic changes even slightly, the patch either fails silently, inserts in the wrong place, or corrupts syntax. This is not robust automation.

**Fix / mitigation:**
- Patch via an AST-aware tool or a minimal Python patcher that parses source conservatively.
- Validate post-patch syntax with Python compilation.
- Refuse to patch unknown file versions.

---

### Finding 17: Appending Python code to `server.py` is likely syntactically or semantically invalid
**Severity:** HIGH

**Problem:**
The script appends a large block to the end of `server.py` and separately injects route logic with `sed`. There is no guarantee imports exist (`json`, `httpx`, `os`) in the right scope, no guarantee indentation is correct, and no guarantee the inserted branch lands inside the intended control structure. This is a classic source of broken startup.

**Fix / mitigation:**
- Use a proper source transformation or maintain a forked integration patch.
- Run `python -m py_compile` or the project test suite after patching.
- Make patch failure fatal.

---

### Finding 18: Persona/model routing rules are inconsistent and underdefined
**Severity:** MEDIUM

**Problem:**
The spec says “add `CODEX_BRIDGE_URL` to the OpenAI model set or handle model routing,” which is not a concrete implementation. It also mixes persona routing with model family routing and fallback rules in a hand-wavy way. If persona is `codex` and the UI selects a Claude model, behavior becomes implicit and potentially confusing.

**Fix / mitigation:**
- Define a strict routing matrix: persona × model → backend.
- Surface coercions to the user instead of silently changing models.
- Add UI validation to only show compatible models for the persona.

---

## 6. IDEMPOTENCY

### Finding 19: `bootstrap.sh --check` is not actually check-only as described
**Severity:** HIGH

**Problem:**
The script sets `CHECK_ONLY=true` and then ignores it. It still creates directories, rewrites files, installs Codex, patches agentic-ui, and potentially initializes git before validation. That is a direct contradiction of the spec.

**Fix / mitigation:**
- Gate all mutating phases on `CHECK_ONLY`.
- Split provisioning and validation into separate scripts.
- Add tests proving `--check` performs zero writes.

---

### Finding 20: Git initialization logic is not safely repeatable
**Severity:** MEDIUM

**Problem:**
On first run it commits everything. On subsequent runs it rewrites generated files but does not create a new commit, so the repo drifts dirty. There is also no handling for missing git identity, pre-existing repos, or failures when agentic-ui patching produces external modifications not meant to be committed here.

**Fix / mitigation:**
- Detect and report dirty state explicitly.
- Do not auto-commit unless requested.
- Scope commits to the codex-drone repo only.
- Verify git user config before attempting commit.

---

### Finding 21: Symlink idempotency is incomplete
**Severity:** MEDIUM

**Problem:**
The script only repairs links if they are symlinks with the wrong target or absent. If `vault` or `memory/curated` exists as a real directory or file, it leaves it untouched and silently proceeds, violating the expected structure.

**Fix / mitigation:**
- Fail loudly if a required symlink path exists with the wrong type.
- Provide a safe remediation path.

---

### Finding 22: UI patching is not idempotent in the face of partial previous runs
**Severity:** MEDIUM

**Problem:**
The patcher only checks `grep -q 'run_codex_agent'`. If a previous run inserted the function but not the dispatch branch, or inserted one dictionary entry but not the other, subsequent runs skip remediation. Partial state becomes permanent drift.

**Fix / mitigation:**
- Validate each insertion independently.
- Add checksum/version markers around managed blocks.
- Reconcile missing fragments on rerun.

---

## 7. MISSING PIECES

### Finding 23: No authentication, authorization, or audit trail
**Severity:** CRITICAL

**Problem:**
This system executes code on behalf of users, but the spec never defines who is allowed to invoke it, how calls are authenticated, or how to audit what was run. That is an operational and security hole, not a missing enhancement.

**Fix / mitigation:**
- Add caller auth and request signing.
- Log requestor identity, prompt hash, working directory, command lifecycle, and result.
- Protect logs from containing secrets.

---

### Finding 24: No logging or observability plan
**Severity:** HIGH

**Problem:**
There is no structured logging for bridge requests, subprocess lifecycle, exit codes, durations, token usage, retries, errors, or disconnects. When something breaks, Marcus will have no forensic trail beyond a dead UI spinner.

**Fix / mitigation:**
- Add structured logs with request IDs.
- Persist task transcripts and subprocess stderr.
- Export basic health and execution metrics.

---

### Finding 25: No cost controls or budget enforcement
**Severity:** HIGH

**Problem:**
The bridge can spawn unlimited Codex executions with expensive models and no concurrency limit. “Cost tracking” is reduced to passing through optional reported usage numbers from the CLI, assuming those numbers exist. That is not cost control.

**Fix / mitigation:**
- Enforce per-request and daily budgets.
- Limit concurrency and model availability.
- Persist actual usage accounting independent of streamed metadata.

---

### Finding 26: No cleanup strategy for tasks, logs, artifacts, or zombie processes
**Severity:** MEDIUM

**Problem:**
Temporary files, task directories, `memory/inbox` contents, generated reports, and orphaned processes will accumulate indefinitely. The spec explicitly omits teardown and says cleanup is not included by design. That is lazy, not safe.

**Fix / mitigation:**
- Add retention policies and cleanup jobs.
- Prune old task artifacts.
- Reap orphaned subprocesses on startup.

---

### Finding 27: No explicit rollback path for agentic-ui modifications
**Severity:** MEDIUM

**Problem:**
The teardown section says “git checkout personas.py server.py,” assuming the target repo is clean, on git, and has no concurrent local changes. That is not a reliable rollback procedure.

**Fix / mitigation:**
- Create a patch file and reverse patch path.
- Back up files before modification.
- Refuse to patch if target repo is dirty unless forced.

---

## 8. TESTABILITY

### Finding 28: The claimed 29 assertions are mostly structural, not behavioral
**Severity:** HIGH

**Problem:**
Counting files and checking executability does not prove the system works. The hard parts here are behavioral: Codex CLI invocation, JSONL parsing, bridge SSE semantics, timeout/cancellation, path restrictions, UI routing, and failure handling. The verification plan barely touches those.

**Fix / mitigation:**
- Add integration tests that launch the bridge and assert actual streamed events.
- Mock or stub Codex CLI output to test parser behavior.
- Test malformed output, nonzero exit, disconnects, and timeouts.

---

### Finding 29: The “Codex exec smoke test” is too vague to validate anything meaningful
**Severity:** MEDIUM

**Problem:**
“List the contents of this directory and report what you see” only proves some command may have run. It does not validate profile selection, config loading, tool execution, JSON mode, or stable event parsing.

**Fix / mitigation:**
- Smoke test exact required flags and inspect output format.
- Validate machine-readable output against an expected schema.
- Include a negative test for unsupported flags/version mismatch.

---

### Finding 30: No tests for UI patch correctness
**Severity:** MEDIUM

**Problem:**
The most fragile part of the whole plan is modifying `agentic-ui/server.py` and `personas.py`, yet there is no test that the patched app still imports, starts, routes correctly, or displays the new persona.

**Fix / mitigation:**
- Run syntax checks and app startup checks after patching.
- Add minimal HTTP tests for the persona path.
- Verify the persona appears in the UI model/persona list.

---

## 9. OPERATIONAL

### Finding 31: There is no operator-facing runbook
**Severity:** HIGH

**Problem:**
The plan says this is an emergency backup for Claude, but it does not define an actual operational procedure: how Marcus starts the bridge, verifies health, selects the persona, recognizes degraded behavior, reads logs, recovers from failure, or disables the system. “Manual persona switch” is not a runbook.

**Fix / mitigation:**
- Write an operator guide with startup, health checks, log locations, known failure modes, and rollback steps.
- Add a one-command start/stop script.

---

### Finding 32: Health endpoints are nearly meaningless
**Severity:** MEDIUM

**Problem:**
`/health` returns `{"status": "healthy"}` regardless of whether Codex CLI exists, auth is valid, vault is mounted, or the subprocess execution path works. This is a liveness endpoint pretending to be readiness.

**Fix / mitigation:**
- Separate liveness and readiness endpoints.
- Readiness should verify Codex binary presence, config validity, auth availability, and writable task paths.

---

### Finding 33: STATUS.md heartbeat is specified but not actually implemented in the bridge path
**Severity:** MEDIUM

**Problem:**
The contracts say Codex writes heartbeat status in workspace root, but the chat bridge example does nothing to ensure that. There is no wrapper prompt enforcing task tracking, no sidecar writer, and no verification that STATUS.md exists or updates during long runs.

**Fix / mitigation:**
- Either implement heartbeat management outside the model or remove the guarantee.
- Validate heartbeat behavior in end-to-end tests.

---

### Finding 34: Switching back to Claude is not operationally defined
**Severity:** LOW

**Problem:**
The spec says Codex is a persona you select when needed, but there is no note on how to revert active conversations, whether histories are compatible, or whether persona state bleeds across sessions.

**Fix / mitigation:**
- Document persona switch expectations.
- Start Codex in separate conversations to avoid context confusion.

---

## 10. SCOPE CREEP

### Finding 35: The design is overbuilt for an “emergency backup,” yet still underbuilt on the critical path
**Severity:** HIGH

**Problem:**
This tries to deliver workspace bootstrap, memory plumbing, vault integration, CLI install, bridge service, Docker option, UI integration, task API ideas, generator scripts, validation scripts, and git automation in one shot. That is a lot of surface area for a backup path that supposedly exists for emergencies. Meanwhile the essential path—“can Marcus invoke Codex safely and reliably from the UI when Claude is down?”—is not actually hardened.

**Fix / mitigation:**
- Cut to a minimum viable backup: verified Codex CLI install, a tiny authenticated bridge with fixed workspace, one health check, and manual UI configuration.
- Defer vault write access, Docker, task APIs, generators, and sed patching until the core flow is proven.

---

### Finding 36: The generators and canonical-content approach adds complexity without solving the hard risks
**Severity:** MEDIUM

**Problem:**
The plan optimizes for reproducible file generation but the real problems are process control, security boundaries, and integration correctness. Generating 900 lines of scaffolding from heredocs does not make the system safer or more reliable; it just makes diffs noisier and debugging worse.

**Fix / mitigation:**
- Keep static files as normal source files unless regeneration is genuinely needed.
- Invest engineering effort in integration tests and runtime safeguards instead.

---

## Summary Verdict

**Verdict: REJECT**

This specification is not ready for implementation. The core architecture rests on unverified assumptions about the Codex CLI interface, exposes an unauthenticated code-execution bridge to the host, grants excessive filesystem access, and relies on brittle patching of another application’s source tree. The validation plan is mostly cosmetic and does not test the failure modes that matter. For an “emergency backup,” it is simultaneously too complicated and not operationally safe.

The minimum bar before reconsideration should be:
1. Verify the real Codex CLI contract and pin a supported version.
2. Replace unauthenticated localhost execution with a restricted, authenticated bridge.
3. Remove broad RW vault access by default.
4. Add process timeouts, cancellation, and concurrency limits.
5. Replace `sed` patching with a robust integration method.
6. Add real behavioral integration tests.

Until those are addressed, this should not be deployed on a machine with real vault or project access.
