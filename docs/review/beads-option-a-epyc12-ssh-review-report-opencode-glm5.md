# Beads Option A Review Report

Feature-Key: bd-pj1lk
Reviewer: opencode-glm5
Date: 2026-04-12
Verdict: adopt_with_blockers

## Executive Verdict

Option A is the correct P0 path. The current fleet model runs remote `bd` clients
against epyc12's Dolt SQL port over Tailscale, which the upstream Beads
architecture does not support as a low-latency coordination model. Every `bd`
command issues multiple sequential SQL round trips; at 75–120ms RTT, those
amplify into 20–48s command latencies on non-local hosts. Running `bd` on epyc12
via Tailscale SSH collapses all those SQL calls to localhost hops.

The trade is simple: one SSH connection setup (~50–200ms with ControlMaster)
replaces dozens of sequential cross-host SQL round trips. For mutations, this is
a clear win. For reads, it would be a regression — local reads must remain
local.

This verdict is **adopt_with_blockers** because three issues must be resolved
before fleet-wide cutover, and one design decision (read/write split) must be
made explicitly. None of these blockers require upstream Beads changes; all are
implementable in the DX layer.

## Top Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | **Command injection in SSH wrapper** | P0 blocker | Strict subcommand allowlist + shell-escaped arguments |
| 2 | **Reads proxied through SSH add unnecessary latency** | P1 blocker | Split: reads local, mutations SSH; require separate BEADS_DOLT_SERVER_HOST for reads |
| 3 | **CWD/BEADS_DIR wrong when running remotely** | P1 blocker | Wrapper sets BEADS_DIR=~/.beads-runtime/.beads explicitly, never relies on cwd |
| 4 | **Actor attribution lost — all mutations appear from epyc12** | P1 | Pass --actor or BEADS_ACTOR env through wrapper |
| 5 | **No ControlMaster → repeated SSH handshake per command** | P1 | Deploy ~/.ssh/config with ControlMaster across fleet |
| 6 | **epyc12 SPOF for mutations** | P2 (accepted) | Already SPOF as Dolt host; no regression |
| 7 | **Argument quoting for titles with special chars** | P2 | Adversarial test suite |
| 8 | **Tailscale down → all mutations blocked** | P2 (accepted) | Same as today; health check in dx-check |
| 9 | **bd binary version drift between caller and epyc12** | P2 | Version gate in wrapper preflight |

## Robustness Review

### epyc12 Availability

epyc12 is already the Dolt server SPOF. Option A does not increase the failure
surface — it changes the transport from MySQL-over-Tailscale to SSH-over-Tailscale.
SSH failure is atomic: a command either completes or fails entirely. Remote SQL
can fail mid-transaction, leaving Dolt in an uncertain state that may require
`bd doctor --fix`.

**Failure mode comparison:**

| Failure | Current (remote SQL) | Option A (SSH) |
|---------|---------------------|----------------|
| Tailscale down | SQL conn refused | SSH conn refused |
| epyc12 reboot | SQL drops mid-tx | SSH terminates; bd gets SIGTERM |
| Dolt server crash | SQL errors; partial state possible | Same; local bd on epyc12 handles restart |
| Network partition | Partial SQL failures | SSH fails cleanly |

**Assessment:** Robustness is equivalent or slightly better under Option A.

### Tailscale SSH Failure Modes

Tailscale SSH adds a layer beyond raw TCP:

1. **Auth latency:** First connection requires Tailscale cert exchange (~1–3s).
   ControlMaster eliminates this for subsequent connections.
2. **Cert expiry:** Tailscale SSH certs rotate. Long-running SSH sessions may
   break. Unlikely for `bd` commands (seconds, not hours).
3. **ACL changes:** If Tailscale ACLs are tightened, SSH access can break
   silently. Document the required ACL rules.
4. **Tailscale daemon down:** If `tailscaled` crashes on either side, SSH
   fails. Add `tailscale status` to dx-check.

**Mitigation:** Deploy `~/.ssh/config` with:

```
Host epyc12
  ControlMaster auto
  ControlPath ~/.ssh/sockets/%r@%h-%p
  ControlPersist 600
  ServerAliveInterval 30
  ServerAliveCountMax 3
```

### Concurrent Writes from Multiple Agents

Multiple agents SSH-ing to epyc12 and running `bd` concurrently is the intended
operating mode for Dolt server mode. All processes become local clients hitting
`127.0.0.1:3307`. The `withRetryTx` pattern in `store.go` handles serialization
failures with exponential backoff. This is designed for local concurrent writers.

**Assessment:** No regression. Actually improves: today's remote SQL connections
have higher lock contention due to longer transaction durations caused by RTT
amplification.

### Multi-Command Graph Creation Races

`bd create --graph <file>` uses `CreateIssuesInTx` which runs inside a single
transaction. This is safe under SSH proxying — transaction boundaries are
preserved.

For multi-step workflows (`bd create` + `bd dep add` + `bd comments add`), each
step is a separate transaction today and remains separate under Option A. No
new race conditions are introduced.

### Failure Atomicity and Partial Mutation Behavior

SSH provides better atomicity than remote SQL:
- SSH command exit code directly reflects `bd` success/failure
- No partial SQL state possible (the remote `bd` either commits or rolls back)
- If SSH connection drops mid-command, `bd` on epyc12 receives SIGTERM and
  rolls back the current transaction

**Risk:** If `bd` auto-commits Dolt after each write (embedded mode default),
a partial multi-step workflow could leave some steps committed and others not.
This is the same risk as today. In server mode, auto-commit is off by default,
which is the correct setting for the epyc12 hub.

### Recovery Model

Recovery under Option A is simpler:
1. `bd` command fails → check exit code, retry once
2. SSH fails → check Tailscale, check epyc12 uptime
3. Dolt corruption → `bd doctor --fix` on epyc12 (same as today)

No new recovery paths are introduced. The existing bd-doctor and
beads-dolt-fleet skills remain valid.

## Speed Review

### Expected Latency vs Remote Dolt SQL

| Host | Current (remote SQL) | Option A (SSH) | Delta |
|------|---------------------|----------------|-------|
| epyc12 | ~0.5s (local) | ~0.5s (local, passthrough) | 0 |
| epyc6 | ~2s | ~1s (SSH + local bd) | -1s |
| homedesktop-wsl | ~20s (bd create) | ~2s (SSH + local bd) | -18s |
| MacBook Pro | ~5–14s (reads), unusable (mutations) | ~2–3s (SSH + local bd) | major |

SSH overhead: ~50ms with ControlMaster (persistent), ~200ms without.
bd command on epyc12: ~0.5–1s for mutations.

### Command Startup Overhead

Without ControlMaster: ~200ms SSH handshake per command.
With ControlMaster: ~5ms for subsequent commands on the same socket.

**Requirement:** ControlMaster must be deployed before rollout. Without it,
the wrapper adds ~200ms per `bd` invocation, which is acceptable for mutations
but would be a regression for tight orchestration loops that read status
frequently.

### Wrapper Overhead

The `bdx` wrapper adds:
1. Argument parsing: ~1ms
2. Allowlist check: ~1ms
3. SSH invocation: ~5–200ms (depends on ControlMaster)
4. Output capture and return: ~1ms

Total wrapper overhead: ~8–203ms. Acceptable for mutations. Unacceptable for
reads in tight loops.

### When Remote Execution Helps vs Hurts

**Helps (mutations):**
- `bd create`, `bd close`, `bd update`, `bd dep add`, `bd comments add`
- All perform multiple SQL writes that benefit from localhost access

**Hurts (reads in tight loops):**
- `bd ready --json` in dx-runner polling (5-minute intervals)
- `bd show <id> --json` in orchestration loops
- `bd list --json` for status checks

**Must remain local (reads):**
- `bd dolt test --json` (health check)
- `bd ready --json` (polling)
- `bd show` (status queries)
- `bd list` (inventory queries)
- `bd search` (text search)

### Paths That Must Remain Local

Read-only commands must continue to use remote Dolt SQL (BEADS_DOLT_SERVER_HOST
pointing to epyc12:3307). This is the existing configuration and works fine for
reads — the RTT penalty is proportional, not amplified, because reads issue
fewer SQL round trips than mutations.

The wrapper contract must explicitly split:

| Command class | Transport | Rationale |
|---------------|-----------|-----------|
| Mutations (create, close, update, dep, comments) | SSH to epyc12 | RTT amplification kills mutations |
| Reads (list, show, ready, search, dolt test) | Remote SQL | Works fine; SSH would add overhead |
| `bd dolt push/pull` | Local CLI | Must run on host with local dolt data |

## Agent Friendliness Review

### What Agents Need to Know

Agents need to know exactly one thing: **use `bdx` instead of `bd` for
mutations**. The wrapper must be a drop-in replacement that accepts the same
flags and returns the same output format.

For reads, agents continue using `bd` as they do today (connecting to epyc12
via remote SQL).

### Wrapper Command Contract

```bash
# Mutations (proxy through SSH to epyc12)
bdx create "Title" --type feature --priority 1
bdx close bd-xyz --reason "Done"
bdx update bd-xyz --status in_progress
bdx dep add bd-xyz bd-abc --type blocks
bdx comments add bd-xyz "Comment text"

# Reads (local bd, unchanged)
bd list --json
bd show bd-xyz --json
bd ready --json
bd search "keyword" --json
```

**Wrapper behavior:**
1. Parse first argument as subcommand
2. If subcommand is in mutation allowlist: SSH to epyc12, run `bd` with all
   args, set `BEADS_DIR=~/.beads-runtime/.beads`, pass `--actor`
3. If subcommand is in read allowlist: reject with error ("use `bd` directly
   for reads")
4. If subcommand is unknown: reject with error and allowlist
5. Exit code mirrors `bd` exit code
6. stdout/stderr passed through unchanged

### Forbidden Raw `bd` Patterns

After rollout, the following must be forbidden on non-epyc12 hosts:

1. **`bd create`** — must use `bdx create`
2. **`bd close`** — must use `bdx close`
3. **`bd update`** (when mutating status/assignee) — must use `bdx update`
4. **`bd dep add/remove`** — must use `bdx dep add/remove`
5. **`bd comments add`** — must use `bdx comments add`
6. **`bd config set`** (global mutations) — must use `bdx config set`

Exception: on epyc12 itself, `bd` works directly (no wrapper needed).

### AGENTS.md Baseline Changes

Section 1.5 (Canonical Beads Contract) must be updated:

1. Add: "On non-epyc12 hosts, use `bdx` for all Beads mutations. `bdx` proxies
   to epyc12 via Tailscale SSH."
2. Add: "On non-epyc12 hosts, use `bd` directly for reads (list, show, ready,
   search, dolt test). These connect to epyc12's Dolt SQL port as before."
3. Add: "On epyc12, use `bd` directly for all operations."
4. Modify: "Before dispatch: verify `bd dolt test --json` succeeds (reads) AND
   `bdx show bd-test --json` succeeds (mutations via SSH)."
5. Add: "`bdx` preflight checks: SSH connectivity to epyc12, matching `bd`
   version on epyc12, BEADS_DIR set correctly."

### Skill Updates Needed

| Skill | Change |
|-------|--------|
| **bd-doctor** | Add `bdx` connectivity check; add SSH health probe |
| **beads-dolt-fleet** | Add `bdx` status to fleet verification |
| **beads-workflow** | Replace `bd create/close/update/dep/comments` with `bdx` equivalents on non-epyc12 |
| **create-pull-request** | Replace mutation `bd` calls with `bdx` |
| **finish-feature** | Replace mutation `bd` calls with `bdx` |
| **fix-pr-feedback** | Replace mutation `bd` calls with `bdx` |
| **session-end** | Add `bdx` health check to session verification |
| **dx-runner** | Preflight must verify `bdx` connectivity when not on epyc12 |
| **implementation-planner** | Replace mutation `bd` calls with `bdx` |

### Script Names and Ergonomics

- **`bdx`**: Main wrapper. Drop-in replacement for `bd` mutations.
- **`bdx-check`**: Health check. Verifies SSH connectivity, `bd` version match,
  BEADS_DIR, and Dolt server status on epyc12.
- **`bdx-preflight`**: Pre-dispatch check. Runs `bdx-check` + `bd dolt test`.

Location: `~/agent-skills/scripts/bdx` (or `~/bin/bdx` for PATH convenience).

## Testing Plan

### Unit Tests

1. **Argument parsing**: Verify all `bd` flags pass through correctly
2. **Allowlist enforcement**: Verify mutation commands route to SSH, read
   commands are rejected, unknown commands are rejected
3. **Quoting**: Test titles with single quotes, double quotes, backticks,
   newlines, dollar signs, semicolons, pipe characters
4. **Exit code passthrough**: Verify `bdx` exit code matches `bd` exit code
5. **Actor propagation**: Verify `--actor` is set correctly based on calling
   host

### Integration Tests

1. **Round-trip**: `bdx create` → `bd show` (read local) → verify issue exists
2. **Dependency creation**: `bdx create` + `bdx dep add` → verify graph
3. **Close workflow**: `bdx create` → `bdx update --status in_progress` →
   `bdx close` → verify status
4. **Comments**: `bdx comments add` → verify comment content
5. **Graph creation**: `bdx create --graph` → verify atomic creation
6. **Dry-run**: `bdx create --dry-run` → verify no mutation

### Fleet Smoke Tests

1. Run from each non-epyc12 host: `bdx create "test from <host>"`
2. Verify on epyc12: `bd show <id>` shows correct actor attribution
3. Verify read: `bd show <id>` from caller host sees the issue
4. Run concurrent: 3 agents from 3 hosts creating issues simultaneously
5. Verify no collisions or data loss

### Concurrency Tests

1. **2 agents, same host**: Create issues concurrently via `bdx`
2. **2 agents, different hosts**: Create issues concurrently via `bdx`
3. **Agent + epyc12 local**: Remote `bdx create` + local `bd create` on epyc12
   simultaneously
4. **Dependency race**: Two agents add dependencies to the same issue
   concurrently

### Timeout and Degraded-Mode Tests

1. **SSH timeout**: Kill SSH connection mid-command → verify clean failure
2. **Tailscale down**: Stop tailscaled → verify `bdx` fails with clear error
3. **Dolt server down on epyc12**: Stop beads-dolt.service → verify `bdx`
   reports Dolt error (not SSH error)
4. **Slow epyc12**: CPU load on epyc12 → verify `bdx` still completes within
   reasonable time

### Fresh-Device Bootstrap Tests

1. New VM with Tailscale + `bd` installed but no SSH config → verify `bdx`
   fails with actionable error pointing to SSH setup
2. New VM with SSH config but no ControlMaster → verify `bdx` works but warns
   about performance
3. Fresh clone with `bd init` → verify `bdx` works immediately

## Security Review

### Tailscale SSH Assumptions

Tailscale SSH authenticates using the Tailscale identity, not SSH keys. This
means:

1. **Identity tied to Tailscale account**: Any device authenticated in the
   Tailscale tailnet can SSH to epyc12 (subject to ACLs)
2. **No secret management**: No SSH private keys to protect
3. **Audit trail**: Tailscale logs all SSH connections in the admin console

**Risk:** If a Tailscale device is compromised, the attacker can SSH to epyc12
and run `bd` commands. Mitigate with Tailscale ACLs that restrict SSH access
to specific devices/users.

### Command Injection Risks in Wrapper Design

This is the **P0 blocker**. The wrapper must never allow arbitrary command
execution on epyc12.

**Threat model:** An agent (or compromised input) could craft a `bd` title
argument like `"; rm -rf /` or `$(malicious_command)`.

**Mitigations:**

1. **Strict subcommand allowlist**: Only known `bd` subcommands are permitted.
   No shell metacharacters in the subcommand position.
2. **Argument escaping**: All arguments must be properly shell-escaped before
   being passed to SSH. Use `printf '%q'` or equivalent.
3. **No `eval` or `$()`**: The wrapper must never use `eval` or command
   substitution on user-supplied arguments.
4. **No `--` passthrough for unknown flags**: Only known `bd` flags are
   forwarded.

**Recommended implementation pattern:**

```bash
#!/usr/bin/env bash
set -euo pipefail

MUTATION_COMMANDS="create close update dep comments config remember forget"
BEADS_DIR="$HOME/.beads-runtime/.beads"
EPYC12_HOST="epyc12"

subcmd="${1:-}"
if [[ ! " $MUTATION_COMMANDS " =~ " $subcmd " ]]; then
  echo "bdx: '$subcmd' is not a mutation command. Use 'bd' for reads." >&2
  echo "Mutation commands: $MUTATION_COMMANDS" >&2
  exit 1
fi

# Build argument array with proper escaping
args=()
for arg in "$@"; do
  args+=("$(printf '%q' "$arg")")
done

exec ssh "$EPYC12_HOST" \
  "BEADS_DIR=$BEADS_DIR bd ${args[*]}"
```

**Note:** The `printf '%q'` approach is the minimum. For production, prefer
passing arguments via SSH's stdin or a temporary file to avoid shell escaping
entirely.

### Allowed Command Allowlist

| Command | Allowed via bdx | Rationale |
|---------|-----------------|-----------|
| `bd create` | Yes | Mutation |
| `bd close` | Yes | Mutation |
| `bd update` | Yes | Mutation |
| `bd dep add` | Yes | Mutation |
| `bd dep remove` | Yes | Mutation |
| `bd comments add` | Yes | Mutation |
| `bd config set` | Yes | Mutation (scoped) |
| `bd remember` | Yes | Mutation |
| `bd forget` | Yes | Mutation |
| `bd list` | No | Read — use `bd` |
| `bd show` | No | Read — use `bd` |
| `bd ready` | No | Read — use `bd` |
| `bd search` | No | Read — use `bd` |
| `bd dolt test` | No | Read — use `bd` |
| `bd dolt push` | No | Must run locally |
| `bd dolt pull` | No | Must run locally |
| `bd init` | No | Must run locally |
| `bd doctor` | No | Must run locally |

### Secret Handling

No new secrets are introduced. Tailscale SSH uses the existing Tailscale
identity. No SSH private keys, no passwords, no tokens.

The `BEADS_DIR` and `bd` configuration on epyc12 are already accessible to
anyone who can SSH to epyc12. Option A does not expand this access.

### Audit Trail and Actor Attribution

**Problem:** All `bdx` mutations appear as coming from the epyc12 user, losing
the originating host/agent identity.

**Solution:** The wrapper must pass actor attribution:

```bash
BDX_ACTOR="${BDX_ACTOR:-$(hostname)-agent}"
exec ssh "$EPYC12_HOST" \
  "BEADS_DIR=$BEADS_DIR BD_ACTOR='$BDX_ACTOR' bd ${args[*]}"
```

Or use `--actor` flag if `bd` supports it. If `bd` does not support `--actor`,
file an upstream issue; this is a real gap.

## Observability and Recovery

### Health Checks

Add to dx-check:

1. `bdx-check`: Verifies SSH connectivity, `bd` version match, BEADS_DIR, Dolt
   server status
2. `bd dolt test --json`: Existing read-path health check (unchanged)
3. `tailscale status | grep epyc12`: Verify Tailscale connectivity

### Logs

- `bdx` should log to `~/logs/dx/bdx.log` with timestamp, command, exit code,
  duration
- SSH commands on epyc12 are logged by Tailscale SSH (audit trail)
- `bd` commands on epyc12 log to existing Dolt logs

### Metrics

- `bdx_command_duration_seconds`: Histogram of command durations
- `bdx_command_success_total`: Counter of successful commands
- `bdx_command_failure_total`: Counter of failed commands, by reason
- `bdx_ssh_overhead_seconds`: SSH connection setup time

### dx-check/fleet-sync Integration

`bdx-check` should be added to the standard `dx-check` run on all hosts. It
should verify:

1. SSH to epyc12 succeeds
2. `bd --version` on epyc12 matches local version (within minor version)
3. `BEADS_DIR` is set correctly on epyc12
4. Dolt server is active on epyc12
5. ControlMaster socket is active (warning if not)

### How Agents Report Failures

Agents should interpret `bdx` failures as follows:

| Symptom | Diagnosis | Action |
|---------|-----------|--------|
| SSH connection refused | Tailscale/epyc12 down | Check Tailscale, check epyc12 |
| SSH hangs | Network issue | Timeout, retry once |
| `bd` error on epyc12 | Dolt/server issue | Run `bd-doctor` on epyc12 |
| Version mismatch | `bd` drift | Update `bd` on caller or epyc12 |
| `BEADS_DIR` error | Config drift | Fix BEADS_DIR on epyc12 |
| Permission denied | Tailscale ACL | Check Tailscale ACLs |

## Low Founder Cognitive Load Assessment

### Number of Decisions Exposed to Founder

**Before rollout:** 3 decisions needed
1. Confirm read/write split strategy
2. Confirm `bdx` naming convention
3. Confirm rollout timing

**After rollout:** 0 ongoing decisions. The wrapper is a drop-in replacement.

### Recovery Burden

Recovery is the same or simpler than today:
- SSH failure → clear error, single retry
- Dolt failure → same recovery as today (bd-doctor on epyc12)
- No new recovery procedures needed

### Whether Failures Are Actionable

Yes. `bdx` failures produce clear, actionable error messages:
- SSH connectivity → "Cannot reach epyc12 via SSH. Check Tailscale."
- Version mismatch → "bd version X on epyc12, Y locally. Update required."
- Dolt error → Same as today's `bd` error messages (passed through)

### Whether This Avoids Sync/Force-Push Decisions

Yes. Option A eliminates the need for Dolt data-dir tar-copy convergence
(`beads-dolt-fleet` converge-from-source). Since all mutations happen on epyc12,
there is one source of truth. Spokes only read, so they can't diverge.

The `beads-dolt-fleet` skill's converge operation becomes unnecessary for
mutation divergence (only needed for catastrophic Dolt corruption recovery).

### Whether Agents Can Self-Diagnose

Mostly yes, with one gap:

- SSH failures: Self-diagnosable (check Tailscale, retry)
- Dolt errors: Self-diagnosable (pass-through from bd)
- **Actor attribution gaps**: Not immediately self-diagnosable. An agent may
  not realize its mutations are attributed to epyc12 instead of itself. The
  `--actor` flag must be consistently applied.

## Things The Prompt Missed

### 1. `bd config set beads.role` Breaks Under SSH

The current self-heal for `beads.role not configured` runs `bd config set
beads.role maintainer` locally. Under Option A, if `beads.role` is misconfigured
on epyc12, the agent on macmini would need to SSH to epyc12 to fix it. The
bd-doctor skill must be updated to handle this case.

### 2. `bd create` Branch Creation Side Effect

`bd create` with the beads-workflow skill auto-creates a git branch. Under SSH,
the git operation runs on epyc12, not the caller's worktree. This is a
**semantic mismatch**: the agent expects the branch in its local worktree, but
the branch is created in epyc12's canonical repo.

**Resolution:** The `bdx` wrapper must NOT proxy git operations. The
beads-workflow skill must be split: `bdx create` for the Beads mutation, then
local `git checkout -b` for the branch. This is a non-trivial skill refactor.

### 3. Hook Execution on Remote

If `bd` hooks (pre-create, post-create) are configured on epyc12, they will
fire during `bdx` mutations. These hooks may reference epyc12-local paths that
don't exist on the calling host. This is acceptable (hooks run where `bd` runs)
but must be documented.

### 4. `bdx` on epyc12 Itself

On epyc12, `bdx` should be a no-op passthrough to `bd` (or a symlink).
Requiring SSH from epyc12 to epyc12 is wasteful and confusing.

### 5. MCP/beads-mcp Compatibility

The beads-mcp server runs locally and may issue both reads and mutations.
If `beads-mcp` is configured on non-epyc12 hosts, it will use `bd` directly
for mutations, bypassing `bdx`. Either:
- `beads-mcp` must be updated to use `bdx` for mutations
- Or `beads-mcp` must only run on epyc12

### 6. Dolt Auto-Commit in Server Mode

Dolt auto-commit is OFF by default in server mode. This means mutations via
`bdx` will not create Dolt commits automatically. The Dolt server handles its
own transaction lifecycle. This is correct behavior but must be documented so
agents don't expect `bd vc log` to show every mutation immediately.

### 7. Version Drift Between Hosts

If `bd` is updated on epyc12 but not on other hosts, `bdx` (which runs the
epyc12 version) may have different flags/behavior than the local version. The
wrapper must check version compatibility before proxying.

## Required Guardrails Before Rollout

### P0 Blockers (Must Fix Before Cutover)

1. **Command injection prevention in `bdx` wrapper**
   - Strict subcommand allowlist
   - Proper argument escaping (printf '%q' or stdin-based approach)
   - No eval, no command substitution on user input
   - Test suite with adversarial inputs

2. **Read/write split enforcement**
   - `bdx` only handles mutations
   - Reads continue via local `bd` with BEADS_DOLT_SERVER_HOST
   - AGENTS.md and all skills updated to reflect split

3. **BEADS_DIR and CWD correctness**
   - Wrapper sets `BEADS_DIR=~/.beads-runtime/.beads` explicitly
   - Wrapper does NOT rely on cwd for Beads resolution
   - Wrapper does NOT proxy `bd init`, `bd dolt push/pull`, or `bd doctor`

### P1 Blockers (Should Fix Before Cutover)

4. **Actor attribution via --actor or BEADS_ACTOR**
   - Wrapper must propagate calling host identity
   - If `bd` doesn't support `--actor`, file upstream issue

5. **ControlMaster deployment**
   - Deploy `~/.ssh/config` with ControlMaster settings to all hosts
   - Add to vm-bootstrap or fleet-deploy

6. **bd-create branch creation split**
   - beads-workflow skill must separate Beads mutation from git branch creation
   - `bdx create` for Beads issue, then local `git checkout -b`

## Required Skill / AGENTS.md / Script Changes

### AGENTS.md Changes

**Section 1.5 additions:**

```markdown
- **On non-epyc12 hosts, use `bdx` for all Beads mutations.** `bdx` proxies
  commands to epyc12 via Tailscale SSH with proper argument escaping.
- **On non-epyc12 hosts, use `bd` directly for reads** (list, show, ready,
  search, dolt test). These connect to epyc12's Dolt SQL port as before.
- **On epyc12, use `bd` directly for all operations.**
- **`bdx` allowlist**: create, close, update, dep, comments, config set,
  remember, forget.
- **`bdx` preflight**: SSH connectivity, bd version match, BEADS_DIR,
  Dolt server active.
```

**Section 1.5 modification:**

```markdown
- **Before dispatch**: verify `bd dolt test --json` succeeds AND `bdx-check`
  passes on the dispatch host (unless on epyc12).
```

### New Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `bdx` | `~/agent-skills/scripts/bdx` | Mutation wrapper (SSH to epyc12) |
| `bdx-check` | `~/agent-skills/scripts/bdx-check` | Health check for bdx connectivity |
| `bdx-preflight` | `~/agent-skills/scripts/bdx-preflight` | Pre-dispatch verification |

### Skill Updates

| Skill | File | Change |
|-------|------|--------|
| bd-doctor | `health/bd-doctor/SKILL.md` | Add `bdx-check` step; add SSH health probe |
| beads-dolt-fleet | `health/beads-dolt-fleet/SKILL.md` | Add `bdx` status to fleet verification |
| beads-workflow | `core/beads-workflow/SKILL.md` | Replace `bd` mutations with `bdx` on non-epyc12 |
| create-pull-request | `core/create-pull-request/SKILL.md` | Replace mutation `bd` calls with `bdx` |
| finish-feature | `core/finish-feature/SKILL.md` | Replace mutation `bd` calls with `bdx` |
| fix-pr-feedback | `core/fix-pr-feedback/SKILL.md` | Replace mutation `bd` calls with `bdx` |
| session-end | `core/session-end/SKILL.md` | Add `bdx-check` to session verification |
| dx-runner | `extended/dx-runner/SKILL.md` | Preflight must verify `bdx-check` on non-epyc12 |
| implementation-planner | `extended/implementation-planner/SKILL.md` | Replace mutation `bd` calls with `bdx` |
| vm-bootstrap | `infra/vm-bootstrap/SKILL.md` | Add `bdx-check` to bootstrap verification |

## Suggested Rollout Sequence

### Phase 1: Infrastructure (1 session)

1. Write `bdx` wrapper with strict allowlist and argument escaping
2. Write `bdx-check` and `bdx-preflight`
3. Deploy `~/.ssh/config` with ControlMaster to all non-epyc12 hosts
4. Add `bdx` to PATH on all hosts
5. Run adversarial test suite against `bdx`

### Phase 2: Validation (1 session)

1. Run fleet smoke tests from all non-epyc12 hosts
2. Run concurrency tests (2+ agents simultaneously)
3. Run timeout and degraded-mode tests
4. Verify actor attribution
5. Verify read/write split

### Phase 3: Skill Updates (1 session)

1. Update AGENTS.md with read/write split and `bdx` documentation
2. Update all skills listed above
3. Run `make publish-baseline` to regenerate AGENTS.md index
4. Deploy updated agent-skills to fleet

### Phase 4: Cutover (1 session)

1. Announce cutover (dx-alerts)
2. Switch all non-epyc12 hosts to `bdx` for mutations
3. Monitor for 24 hours
4. Remove remote-Dolt-SQL mutation path from non-epyc12 hosts
   (keep BEADS_DOLT_SERVER_HOST for reads only)

### Phase 5: Cleanup (deferred)

1. Remove `beads-dolt-fleet` converge-from-source for mutation divergence
2. Deprecate `bd-doctor` spoke connectivity check for mutations
3. Add `bdx` to vm-bootstrap default tool verification

## Open Questions

1. **Does `bd` support `--actor` or `BEADS_ACTOR`?** If not, this must be
   filed as an upstream issue. Actor attribution is essential for fleet
   observability.

2. **Should `bdx` proxy `bd update --status` (which can be read-like)?** The
   `bd update` command can set status, assignee, and other fields. Some uses
   are mutation-only (setting status), others are borderline (claiming). The
   allowlist should include all of `bd update` since it always writes.

3. **What happens to `bd create` branch auto-creation?** The beads-workflow
   skill auto-creates a git branch. Under `bdx`, this branch is created on
   epyc12's filesystem, not the caller's worktree. This needs an explicit
   design decision: either disable branch auto-creation in `bdx`, or split
   the skill into two steps (Beads mutation via `bdx`, then local git branch).

4. **Should `beads-mcp` be updated to use `bdx`?** If `beads-mcp` runs on
   non-epyc12 hosts and issues mutations, it must be updated. Alternatively,
   `beads-mcp` could be restricted to epyc12 only.

5. **What is the `bd` version compatibility window?** If epyc12 has `bd` v0.9.11
   and macmini has v0.9.10, should `bdx` refuse to run? Define a minimum
   compatibility policy.

6. **Should `bdx` support `bd --db` for alternative databases?** If agents
   use `bd --db /tmp/test-beads create "test"`, this flag must pass through
   correctly. Test databases should probably be rejected by the wrapper (they
   should use local `bd`).

## Final Recommendation

**Option A is the correct P0 operational path. Adopt with blockers.**

The current fleet model (remote `bd` clients connecting directly to epyc12's
Dolt SQL port over Tailscale) is an unsupported configuration that produces
catastrophic latency on high-RTT hosts. The upstream Beads architecture is
designed for local or same-machine SQL access.

Option A eliminates the root cause by running `bd` on epyc12 where SQL is
local. The trade — one SSH session per mutation — is a net win: ~50–200ms SSH
overhead replaces 20–48s of RTT-amplified SQL latency.

Three blockers must be resolved before cutover:
1. Command injection prevention (strict allowlist + argument escaping)
2. Read/write split (mutations via SSH, reads via remote SQL)
3. BEADS_DIR/CWD correctness (explicit env, no cwd reliance)

After blocker resolution, cutover should be decisive (per the Founder
Cognitive Load Policy): all non-epyc12 hosts switch to `bdx` for mutations
in a single session, with no dual-path coexistence period.

The SPOF concern (epyc12) is accepted: it is the SPOF today as the Dolt
server host, and Option A does not increase this surface.
