# Beads Option A Review Report

Feature-Key: bd-pj1lk
Reviewer: claude-opus
Date: 2026-04-12
Verdict: adopt_with_blockers

## Executive Verdict

Option A is the correct P0 operational path. The current fleet model — pointing
remote `bd` clients at epyc12's Dolt SQL port over Tailscale — is an unsupported
configuration that suffers from catastrophic RTT amplification. The upstream
Beads architecture explicitly assumes local or same-machine SQL access; it does
not pipeline SQL round trips and was never designed for cross-host MySQL
connections.

Running `bd` commands on epyc12 via Tailscale SSH eliminates the amplification at
the root cause: every SQL call becomes a localhost hop. The single SSH session
setup cost (~50–200ms) replaces 20–48s of accumulated round-trip penalty.

This is a **decisive cutover, not a transition**. The Founder Cognitive Load
Policy applies: no phased rollout, no dual-path coexistence, no parallel
validation. Once the wrapper is validated, cut over all non-epyc12 hosts.

Two blockers must be resolved before rollout. Both are implementable in a single
focused session.

## Top Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | **Command injection in SSH wrapper** | P0 blocker | Strict allowlist + argument escaping (see Security Review) |
| 2 | **No read/write split — reads also pay SSH overhead** | P1 blocker | Local reads must remain local; only mutations proxy through SSH |
| 3 | **SSH ControlMaster not configured → repeated handshake per command** | P1 | Deploy ControlMaster config across fleet |
| 4 | **epyc12 SPOF for mutations** | P2 (accepted) | Already the SPOF today as Dolt server host; no regression |
| 5 | **Argument quoting edge cases (titles with quotes, newlines, special chars)** | P2 | Test suite with adversarial inputs |
| 6 | **Actor/committer attribution lost** | P2 | Pass `--actor` through wrapper, map to calling host |
| 7 | **Tailscale down → all mutations blocked fleet-wide** | P2 (accepted) | Same as today; add health check to dx-check |
| 8 | **CWD/path assumptions in `bd` broken when running remotely** | P1 blocker | Wrapper must set BEADS_DIR explicitly, not rely on cwd |

## Robustness Review

### epyc12 Availability

epyc12 is already the single Dolt server. Option A does not increase the SPOF
surface — it changes the wire protocol from MySQL-over-Tailscale to
SSH-over-Tailscale. If anything, SSH is more robust: it's a single TCP
connection for the full command lifetime vs. many SQL round trips that can
individually fail.

**Failure mode comparison:**

| Failure | Current (remote SQL) | Option A (SSH proxy) |
|---------|---------------------|---------------------|
| Tailscale down | All mutations fail (SQL connection refused) | All mutations fail (SSH connection refused) |
| epyc12 reboot | SQL connections drop mid-transaction | SSH sessions terminate; bd sees SIGTERM |
| Dolt server crash | SQL errors; auto-start may mask issues | Same; local bd on epyc12 handles restart |
| Network partition | Partial SQL failures, possible corruption | SSH fails cleanly; no partial state |

**Assessment:** Robustness is equivalent or slightly better. SSH failure is
atomic (the command either completes fully or fails entirely). Remote SQL can
fail mid-transaction, requiring Dolt server recovery.

### Concurrent Writes

Multiple agents SSH-ing to epyc12 and running `bd` concurrently is the **intended
operating mode** for Dolt server mode. All processes become local clients
hitting `127.0.0.1:3307` — exactly what the upstream architecture supports.

The `withRetryTx` pattern in `store.go:612` handles serialization failures with
exponential backoff. This is designed for local concurrent writers and works
correctly when all clients are on the same host.

### Multi-Command Graph Creation Races

`bd create --graph <file>` uses `CreateIssuesInTx` (issueops/create.go:107)
which runs inside a single transaction. SSH-proxying this is safe — the
transaction boundaries don't change.

For multi-step workflows (`bd create` + `bd dep add` + `bd comments add`), each
command is a separate SSH session. This is the same isolation model as running
them locally — no additional race conditions introduced.

### Failure Atomicity

If SSH drops mid-command:
- The remote `bd` process receives SIGHUP (SSH session termination)
- If inside a SQL transaction, the transaction rolls back (Dolt/MySQL behavior)
- If after DOLT_COMMIT but before SSH exit: the commit is durable, but the caller
  sees an error. This is idempotent for most operations.

**Risk:** `doltAddAndCommit` (store.go:1649) stages tables then commits in
sequence. If SSH drops between DOLT_ADD and DOLT_COMMIT, the staged changes
remain in the working set. This is recoverable via `bd doctor --fix` and is no
worse than killing a local `bd` process.

### Recovery Model

Same as today: `bd doctor`, `bd doctor --fix`, service restart via systemctl.
No new recovery procedures needed. The wrapper should surface SSH-specific
failures (connection refused, auth failure, timeout) with actionable messages.

## Speed Review

### Expected Latency Comparison

| Operation | Current (homedesktop-wsl, ~75ms RTT) | Option A | Improvement |
|-----------|--------------------------------------|----------|-------------|
| `bd create` (single issue) | ~20s | ~300ms (SSH setup) + ~200ms (local) = ~500ms | **40x faster** |
| `bd dep add` (edge ops) | ~32-48s | ~300ms + ~100ms = ~400ms | **80-120x faster** |
| `bd ready --json` (read) | ~5-14s | ~200ms (local, no SSH) | **25-70x faster** (if reads stay local) |
| `bd show <id> --json` | ~2-5s | ~100ms (local) | **20-50x faster** |

### Why Current Model Is Slow

Each `bd` write command issues multiple sequential SQL round trips:

1. `BEGIN` (1 RTT)
2. `SELECT` existence check (1 RTT)
3. `INSERT INTO issues` (1 RTT)
4. `INSERT INTO events` (1 RTT)
5. `COMMIT` (1 RTT)
6. `CALL DOLT_ADD('issues', 'events')` (1 RTT)
7. `CALL DOLT_COMMIT(...)` (1 RTT)

At ~75ms RTT, that's a minimum of 7 × 75ms = 525ms for a simple create. Complex
commands (`create --graph`, dependency graph operations) can issue 20+ round
trips: 20 × 75ms = 1.5s minimum. Observed times are higher (20-48s) because
some operations do additional reads, retries, and cache invalidation.

### SSH Overhead

- **First connection (no ControlMaster):** ~100-300ms over Tailscale
- **Subsequent connections (with ControlMaster):** ~10-30ms (reuses TCP+auth)
- **Command execution on epyc12:** ~50-200ms (all SQL is localhost)

**ControlMaster is essential.** Without it, each `bd` invocation pays the full
SSH handshake cost. With it, multi-command workflows approach local speed.

Recommended SSH config:

```
Host epyc12
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 600
```

### Paths That Must Remain Local

Read-only commands should **not** be proxied through SSH. They should continue
hitting the Dolt SQL server directly (even with RTT, reads are faster than
adding SSH overhead on top). Specifically:

- `bd list`, `bd ready`, `bd show`, `bd search`, `bd stats`, `bd blocked`,
  `bd count`, `bd graph`, `bd duplicates`, `bd comments` (list), `bd export`

These are already classified in `readOnlyCommands` (main.go:99-113). The wrapper
should respect this classification.

**Critical:** On hosts where the current remote SQL latency is acceptable for
reads (epyc6 at ~1-2ms), there is zero benefit to proxying reads. On high-RTT
hosts (homedesktop-wsl, MacBook), even reads are slow, so proxying reads through
SSH may be faster. The wrapper should start with mutation-only proxying and add
read proxying as a measured optimization.

## Agent Friendliness Review

### What Agents Need To Know

1. **Use `bdx` for mutations on non-epyc12 hosts.** `bd` continues to work for
   reads (pointing at the remote Dolt SQL server).
2. **`bdx` is a transparent wrapper.** Same arguments, same output, same exit
   codes. The only difference is execution location.
3. **JSON output is preserved.** `bdx create --json "title"` returns the same
   JSON as `bd create --json "title"`.
4. **`bdx` is a no-op on epyc12.** If already on the Dolt server host, `bdx`
   falls through to local `bd`.

### Wrapper Command Contract

```bash
# Wrapper: bdx (Beads remote eXecute)
# Location: ~/agent-skills/scripts/bdx
# Behavior: Proxies mutating bd commands to epyc12 via Tailscale SSH

# Usage: identical to bd
bdx create "Issue title" --type feature --priority 1
bdx dep add bd-abc bd-xyz --type blocks
bdx comments add bd-abc "Comment text"
bdx close bd-abc --reason "Done"
bdx update bd-abc --status in_progress

# Read-only commands pass through to local bd
bdx ready --json          # → local bd ready --json
bdx show bd-abc --json    # → local bd show bd-abc --json
bdx list --json           # → local bd list --json

# On epyc12, all commands run locally
bdx create "Issue"        # → bd create "Issue" (direct)
```

**Contract guarantees:**

| Property | Guarantee |
|----------|-----------|
| Exit code | Matches remote bd exit code |
| stdout | Byte-for-byte passthrough from remote bd |
| stderr | Byte-for-byte passthrough from remote bd |
| JSON mode | Preserved (`--json` passed through) |
| Actor attribution | `--actor` auto-set to `<hostname>/<agent-id>` if not explicit |
| Timeout | Configurable, default 60s, hard kill at 120s |
| Env passthrough | `BEADS_DIR` set on remote; local env vars NOT leaked |

### Forbidden Raw `bd` Patterns

After cutover, agents on non-epyc12 hosts MUST NOT run raw `bd` for mutations:

```bash
# FORBIDDEN on non-epyc12 hosts after cutover:
bd create ...
bd update ...
bd close ...
bd dep add ...
bd comments add ...

# ALLOWED (reads remain local):
bd ready --json
bd show bd-abc --json
bd list --json
bd search "keyword" --json
```

### Script Names and Ergonomics

- `bdx` — short, memorable, follows the existing `dx-*` naming convention
- Alternative considered: `bd-remote` — too long, breaks muscle memory
- Alternative considered: overriding `bd` with a shell function — too magical,
  breaks debugging, confuses agents that introspect their PATH

## Required Skill / AGENTS.md / Script Changes

### AGENTS.md (Section 1.5: Canonical Beads Contract)

Add after "**`epyc12` is the central Dolt server host**":

```markdown
- **Non-epyc12 hosts MUST use `bdx` for mutating Beads commands** (create, update, close, dep, comments add, etc.).
- **`bdx` transparently proxies mutations to epyc12 via Tailscale SSH**; read-only commands remain local.
- **On epyc12, `bdx` is a passthrough to `bd`** — no behavioral difference.
- **`bd` on non-epyc12 hosts is read-only after Option A cutover.**
```

### Skills To Update

| Skill | File | Change |
|-------|------|--------|
| `bd-doctor` | `health/bd-doctor/SKILL.md` | Add `bdx` connectivity check; verify SSH ControlMaster |
| `beads-dolt-fleet` | `health/beads-dolt-fleet/SKILL.md` | Update fleet check to verify `bdx` works from each spoke |
| `beads-workflow` | `core/beads-workflow/SKILL.md` | Replace `bd create`, `bd update`, etc. with `bdx` equivalents |
| `issue-first` | `core/issue-first/SKILL.md` | Replace `bd create` with `bdx create` |
| `create-pull-request` | `core/create-pull-request/SKILL.md` | Replace `bd close` with `bdx close` |
| `sync-feature-branch` | `core/sync-feature-branch/SKILL.md` | Replace `bd` mutations with `bdx` |
| `session-end` | `core/session-end/SKILL.md` | Add `bdx` health to session end checks |
| `worktree-workflow` | `extended/worktree-workflow/SKILL.md` | No change (doesn't run bd directly) |
| `dx-runner` | `extended/dx-runner/SKILL.md` | Document that dispatched agents should use `bdx` |
| `fleet-deploy` | `infra/fleet-deploy/SKILL.md` | Add `bdx` and SSH ControlMaster config to fleet deploy |

### New Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `bdx` | `scripts/bdx` | Main wrapper (see contract above) |
| `bdx-preflight` | `scripts/bdx-preflight` | Check SSH connectivity + `bd` availability on epyc12 |
| SSH config snippet | `configs/ssh-controlmaster-epyc12.conf` | ControlMaster config for fleet deployment |

### Dist Artifacts

- `dist/dx-global-constraints.md` — add `bdx` contract
- `dist/universal-baseline.md` — regenerate via `make publish-baseline`

## Testing Plan

### Unit Tests (wrapper logic)

| Test | Input | Expected |
|------|-------|----------|
| Read-only detection | `bdx ready --json` | Runs local `bd`, exit 0 |
| Mutation routing | `bdx create "Test"` | SSH to epyc12, runs `bd create "Test"` |
| On-epyc12 passthrough | `bdx create "Test"` (on epyc12) | Runs local `bd create "Test"` |
| Argument escaping | `bdx create "It's a \"test\""` | Correct quoting over SSH |
| Newline in argument | `bdx create "Line1\nLine2"` | Preserved through SSH |
| JSON passthrough | `bdx create --json "Test"` | stdout is valid JSON |
| Exit code forwarding | `bdx create` (no title) | Non-zero exit, same as `bd create` |
| Timeout enforcement | `bdx` with 1s timeout, slow command | Kill after timeout, non-zero exit |
| Unknown subcommand | `bdx notacommand` | Error from remote `bd`, non-zero exit |

### Integration Tests

| Test | Steps | Pass Criteria |
|------|-------|---------------|
| Create + show round trip | `bdx create "Test" --json`, capture ID, `bd show <id> --json` | Issue visible locally |
| Dependency creation | `bdx create` x2, `bdx dep add`, `bd show` deps | Dependency visible |
| Comment creation | `bdx comments add bd-xxx "text"`, `bd show` | Comment present |
| Graph creation | `bdx create --graph graph.json --json` | All issues + deps created atomically |
| Concurrent mutations | 3 parallel `bdx create` from same host | All 3 issues created, no errors |
| Cross-host concurrent | `bdx create` from homedesktop-wsl + macmini simultaneously | Both succeed |

### Fleet Smoke Tests

```bash
# Run from each non-epyc12 host:
for host in macmini homedesktop-wsl epyc6; do
  ssh $host 'bdx-preflight && bdx create --json "smoke-test-$(hostname)-$(date +%s)" --type task --priority 4'
done
```

### Concurrency Tests

```bash
# 5 parallel creates from one host
seq 5 | xargs -P5 -I{} bdx create --json "concurrent-{}" --type task --priority 4

# 3 hosts × 3 parallel creates = 9 concurrent mutations
for host in macmini homedesktop-wsl epyc6; do
  ssh $host 'seq 3 | xargs -P3 -I{} bdx create --json "concurrent-$(hostname)-{}" --type task --priority 4' &
done
wait
```

### Timeout and Degraded-Mode Tests

| Test | Setup | Expected |
|------|-------|----------|
| SSH timeout | Block Tailscale to epyc12 | `bdx` fails within timeout, clear error |
| epyc12 bd missing | Rename bd binary on epyc12 | `bdx` fails, error mentions missing binary |
| Dolt server down on epyc12 | Stop beads-dolt service | `bdx` fails, error from `bd` (connection refused) |
| ControlMaster stale | Kill SSH control socket | Next command re-establishes cleanly |

### Fresh-Device Bootstrap Test

```bash
# On a new VM with Tailscale but no Beads config:
# 1. Install bdx
cp ~/agent-skills/scripts/bdx ~/.local/bin/
# 2. Configure SSH ControlMaster
cp ~/agent-skills/configs/ssh-controlmaster-epyc12.conf ~/.ssh/config.d/
# 3. Set env
export BEADS_DIR=~/.beads-runtime/.beads
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
# 4. Preflight
bdx-preflight
# 5. First mutation
bdx create --json "bootstrap-test" --type task --priority 4
# 6. Verify read
bd show $(bdx create --json "verify" | jq -r .id) --json
```

## Security Review

### Tailscale SSH Assumptions

- **Authentication:** Tailscale SSH uses WireGuard-authenticated connections.
  No additional SSH key management needed.
- **Authorization:** Tailscale ACLs control which nodes can SSH to epyc12. The
  current fleet config already permits this.
- **Encryption:** WireGuard provides transport encryption. SSH adds another layer.
- **Network scope:** Tailscale is a private overlay network. No public exposure.

### Command Injection Risk (P0 BLOCKER)

The wrapper constructs an SSH command that includes user-provided arguments:

```bash
# DANGEROUS naive implementation:
ssh epyc12 "bd create $TITLE"
# If TITLE='test"; rm -rf /' → command injection

# SAFE implementation using --:
ssh epyc12 -- bd create "$TITLE"
# SSH's -- separates ssh args from remote command
# But this still expands $TITLE on the local shell

# SAFEST: use explicit argument array
ssh epyc12 bd create -- "$@"
# Still requires careful quoting
```

**Required mitigation:**

1. **Allowlist of `bd` subcommands.** The wrapper MUST reject anything not in:
   `create`, `update`, `close`, `dep`, `comments`, `label`, `reopen`, `claim`,
   `unclaim`, `assign`, `unassign`, `sync`, `config set`, `admin`, `mol`, `vc commit`.
2. **No shell expansion on remote.** Use SSH's direct exec mode (no `-t`, no
   remote shell interpretation). Pass arguments as an array.
3. **No environment variable passthrough** except `BEADS_DIR`.
4. **No stdin passthrough** for the initial version (prevents pipe-based
   injection). Add `--file` support explicitly if needed.

### Allowed Command Allowlist

```bash
MUTATING_SUBCOMMANDS=(
  create update close reopen
  dep comments label
  claim unclaim assign unassign
  admin config
  mol
  vc
  sync
  remember forget
  dolt  # For bd dolt push/pull, but NOT bd dolt start/stop
)
```

### Secret Handling

- `bdx` runs as the same user on epyc12 (Tailscale SSH preserves user identity)
- No secrets transit through the wrapper; `bd` on epyc12 uses its own
  `BEADS_DIR` and env
- 1Password/OP credentials are not needed for `bd` operations
- The only sensitive data in transit is issue content (titles, descriptions) —
  encrypted by Tailscale+SSH

### Audit Trail and Actor Attribution

Currently, `bd` uses the `--actor` flag or defaults to `git config user.name`.
With SSH proxying, all commands appear to originate from epyc12's local user.

**Required:** The wrapper must inject `--actor` with the source host identity:

```bash
bdx create "Issue" → ssh epyc12 bd create "Issue" --actor "macmini/claude-opus"
```

This preserves audit trail in Dolt commit history and Beads event logs.

## Observability and Recovery

### Health Checks

| Check | Command | Frequency |
|-------|---------|-----------|
| SSH connectivity | `ssh -o ConnectTimeout=5 epyc12 true` | Every dx-check cycle |
| Remote bd health | `ssh epyc12 bd doctor quick` | Every fleet-sync cycle |
| ControlMaster alive | `ssh -O check epyc12 2>&1` | Before multi-command workflows |
| Dolt server on epyc12 | `ssh epyc12 systemctl --user is-active beads-dolt.service` | Every dx-check cycle |
| End-to-end mutation | `bdx show <known-id> --json` | Canary check in dx-check |

### Logs

- SSH connection logs: local syslog / `~/.ssh/cm-*` socket files
- Remote bd logs: `~/.beads-runtime/.beads/dolt/sql-server.log` on epyc12
- Wrapper logs (optional): `~/.local/var/log/bdx.log` with timestamps + args

### Metrics (Future)

- `bdx_command_duration_seconds` (histogram by subcommand)
- `bdx_ssh_connect_duration_seconds`
- `bdx_error_total` (counter by error type: ssh_refused, ssh_timeout, bd_error)

### dx-check / fleet-sync Integration

Add to `dx-check`:

```bash
# Beads mutation path health
if [[ "$(hostname)" != "epyc12" ]]; then
  bdx-preflight || echo "WARN: bdx mutation path unhealthy"
fi
```

### How Agents Report Failures

`bdx` should exit with structured error codes:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | Remote bd error (pass through) |
| 2 | SSH connection failed |
| 3 | SSH timeout |
| 4 | Command not in allowlist |
| 5 | Preflight failed |

Agents can switch on exit code to determine whether to retry (2, 3) or
escalate (1, 4, 5).

## Low Founder Cognitive Load Assessment

### Decisions Exposed to Founder

| Decision | Answer | Status |
|----------|--------|--------|
| Should we do Option A? | Yes (this review) | Pending founder approval |
| What's the wrapper name? | `bdx` | Pre-decided, overridable |
| ControlMaster config? | Yes, deploy fleet-wide | Automated via fleet-deploy |
| Read/write split? | Yes, mutations only through SSH | Pre-decided |

**Total founder decisions: 1** (approve or reject Option A). Everything else
is pre-decided with sensible defaults.

### Recovery Burden

| Failure | Recovery | Founder Involvement |
|---------|----------|---------------------|
| SSH to epyc12 down | Wait for Tailscale reconnect; agents auto-retry | None |
| Dolt server crash | `systemctl --user restart beads-dolt.service` on epyc12 | Same as today |
| bdx bug | Fix in agent-skills, fleet-deploy | Same as any script fix |
| ControlMaster stale | Auto-recovers on next connection | None |

**Assessment:** Recovery burden is equivalent or lower than today. No new
failure modes require founder intervention. The SSH ControlMaster auto-heals.

### Sync/Force-Push Decisions

Option A completely avoids:
- Dolt push/pull decisions across hosts
- Sync replica configuration
- Force-push recovery
- Merge conflict resolution across Dolt instances

All mutations happen on one host. There is one Dolt database. Zero distribution
complexity for the mutation path.

### Agent Self-Diagnosis

`bdx-preflight` lets agents diagnose their own connection health before
attempting mutations. This eliminates the founder-as-debugger anti-pattern
where agents report cryptic SQL errors and the founder has to interpret them.

## Things The Prompt Missed

### 1. BEADS_DIR and CWD Semantics

`bd` discovers its database via `beads.FindBeadsDir()` which walks up from
the current working directory (main.go:147). When running via SSH, the remote
cwd is the user's home directory on epyc12, not the agent's working directory.

**The wrapper MUST explicitly set `BEADS_DIR=~/.beads-runtime/.beads`** on the
remote command. The current fleet already uses this path, so this is not a new
requirement, but the wrapper must enforce it — relying on cwd-based discovery
would break.

### 2. Interactive Commands

Some `bd` subcommands are interactive (e.g., `bd init`, `bd federation add-peer`
with password prompts). The wrapper should reject these — they cannot work over
SSH without TTY forwarding, and agents should not be running them.

### 3. Large Argument Payloads

`bd create --graph <file>` reads from a file. Over SSH, the file must exist on
epyc12 or be streamed via stdin. The wrapper needs a `--file` mode that copies
the file to epyc12 (via scp or stdin pipe) before executing `bd create --graph`.

Alternatively, for `--graph` and `--file` flags, the wrapper could:
1. Read the file locally
2. Base64-encode it
3. Pass it as an inline argument via heredoc

This is a P2 concern — the initial wrapper can simply require graph files to
exist on epyc12 (which they will in `/tmp/agents/` worktrees if the agent is
dispatched there).

### 4. `bd dolt push/pull` Special Handling

`bd dolt push` and `bd dolt pull` are already documented as using the `dolt`
CLI (not the SQL server) for SSH remotes. These commands run local file I/O on
the Dolt data directory. They MUST run on epyc12 (where the data lives), so
they should be in the mutation allowlist.

### 5. `bd config set` is Host-Specific

Running `bd config set` via SSH affects epyc12's config, not the calling host's.
This is probably correct (the calling host doesn't run Dolt), but agents need
to know that `bdx config set` modifies the shared server config, not their
local config.

### 6. Metrics/Telemetry

`bd` has OpenTelemetry instrumentation (store.go imports `go.opentelemetry.io/otel`).
When running via SSH, telemetry is emitted from epyc12, not the calling host.
The `--actor` injection preserves agent identity for attribution, but spans
will show epyc12 as the host. This is acceptable but should be documented.

## Required Guardrails Before Rollout

### P0 Blockers (Must Fix)

1. **Command injection protection:** Implement allowlist + proper SSH argument
   passing without shell expansion on the remote side.
2. **BEADS_DIR enforcement:** The wrapper must always set
   `BEADS_DIR=~/.beads-runtime/.beads` on the remote command, never relying on
   cwd-based discovery.
3. **Read/write split:** Read-only commands must NOT be proxied. The wrapper
   must classify commands using the same `readOnlyCommands` map from main.go.

### P1 Required (Before Fleet-Wide Cutover)

4. **SSH ControlMaster config deployed** to all spoke hosts.
5. **Actor attribution** via `--actor` injection.
6. **Structured exit codes** for agent error handling.
7. **`bdx-preflight` script** for pre-dispatch validation.
8. **AGENTS.md updated** with bdx contract and read-only bd policy.

### P2 Nice-to-Have (Post-Cutover)

9. File argument handling (`--graph`, `--file`) via stdin streaming.
10. Read proxying for high-RTT hosts (MacBook, homedesktop-wsl).
11. `bdx` metrics/logging.
12. Automated canary in dx-check.

## Suggested Rollout Sequence

### Phase 1: Implement + Validate (Single Session)

1. Implement `bdx` wrapper with allowlist, argument escaping, BEADS_DIR
2. Implement `bdx-preflight`
3. Deploy SSH ControlMaster config to all fleet hosts
4. Run unit test suite locally
5. Run integration tests from homedesktop-wsl → epyc12

### Phase 2: Cutover (ALL_IN_NOW)

6. Update AGENTS.md Section 1.5
7. Update all affected skills (see table above)
8. Run `make publish-baseline`
9. Fleet-deploy `bdx` and updated configs to all hosts
10. Verify from each spoke: `bdx-preflight && bdx create --json "cutover-test-$(hostname)"`
11. Done. No transition period. No dual-path.

### Phase 3: Cleanup (Next Session)

12. Add `bdx` health check to dx-check
13. Add bdx canary to fleet-sync
14. Document in runbook

## Open Questions

1. **Should `bdx` be a shell script or a Go binary?** Shell script is faster to
   implement and easier to modify. Go binary would be more robust for argument
   handling. Recommendation: start with shell script, graduate to Go if edge
   cases accumulate.

2. **Should reads on high-RTT hosts (MacBook) also proxy through SSH?**
   Measurably slower reads (5-14s) suggest yes, but this increases epyc12 load.
   Defer to Phase 3 measurement.

3. **Should `bdx` support `bd init`?** Probably not — `bd init` is a one-time
   setup command that shouldn't happen through a proxy. Explicitly exclude it.

4. **What happens to the MacBook?** The review brief shows MacBook at ~120ms
   RTT with "mutations often unusable". If the MacBook is used for development,
   it needs `bdx` too. Is it in the canonical fleet?

5. **Should the `bd` binary on spoke hosts be configured differently after
   cutover?** Currently spokes point `BEADS_DOLT_SERVER_HOST` at epyc12. After
   cutover, this is only used for reads. The env var should remain as-is.

## Final Recommendation

**Verdict: ADOPT WITH BLOCKERS**

Option A is the correct architecture. It aligns with the upstream Beads design
(local clients, local SQL), eliminates the root cause of the latency incident
(RTT amplification from remote SQL), and does not introduce new failure modes.

The two P0 blockers (command injection protection and BEADS_DIR enforcement)
are straightforward to implement in the wrapper. The P1 items (ControlMaster,
actor attribution, exit codes) are standard engineering work.

The Founder Cognitive Load Policy is satisfied: this is a binary ALL_IN_NOW
decision with no transition period, no monitoring requirement, and one founder
decision (approve/reject).

The long-term payoff bias applies: one focused implementation session removes
the recurring 20-48s latency tax on every Beads mutation from every non-epyc12
host, permanently.

**Recommendation:** Approve Option A. Schedule one implementation session for
Phase 1 + Phase 2. Cut over fleet-wide immediately after validation.
