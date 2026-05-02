---
name: dx-runner
description: |
  Lower-level unified runner for multi-provider dispatch with shared governance.
  Routes to cc-glm, opencode, claude-code, or gemini providers with unified preflight, gates, and failure taxonomy.
  Use directly for provider debugging, custom orchestration, headless jobs, or when a task-specific shim such as dx-loop, dx-review, or dx-research delegates to it.
tags: [workflow, dispatch, governance, multi-provider, automation]
allowed-tools:
  - Bash
---

# dx-runner: Unified Multi-Provider Dispatch Runner

## Overview

`dx-runner` is the lower-level governed execution substrate for agent dispatch. For chained Beads work, multi-step outcomes, implement/review baton flow, or PR-aware follow-up, use `dx-loop` first.

It provides:

- **Single command surface**: start/status/check/restart/stop/watchdog/report/preflight
- **Multi-provider support**: opencode (primary throughput and the `dx-review` Kimi/DeepSeek quorum), cc-glm (Z.ai/GLM reliability backstop outside the default review quorum), claude-code (native Claude Code lane for explicit non-default use), gemini (optional burst outside the default review quorum)
- **Unified governance**: preflight, permission gates, no-op detection, baseline/integrity/feature-key gates
- **Deterministic outputs**: Machine-readable JSON with stable schemas

Native Claude Code dispatch is implemented as the `claude-code` provider. The `cc-glm` provider remains the Z.ai/GLM wrapper lane and is not Anthropic Claude Code support.

OpenCode behavior in this skill is grounded in official docs and live CLI help:
- [OpenCode CLI docs](https://opencode.ai/docs/cli/)
- [OpenCode server docs](https://opencode.ai/docs/server/)
- `opencode run --help` on the target host (for exact supported flags)

## When To Use

- Provider debugging or custom orchestration that needs direct runner control
- Running headless agent sessions
- Managing parallel agent jobs
- Checking job health with governance gates
- Generating job reports

Task-specific shims should be the default agent entrypoint:

| Outcome Needed | Preferred Surface | Notes |
|---|---|---|
| Chained Beads work / implement-review baton / PR-aware follow-up | `dx-loop` | Default agent-facing orchestrator over `dx-runner` |
| Independent code/design/security review | `dx-review` | Review quorum wrapper over `dx-runner` |
| Source-backed web/deep research + decision memo | `dx-research` | Research artifact wrapper over `dx-runner` |
| Provider debugging, custom orchestration, manual profile control | `dx-runner` | Substrate/manual escape hatch |

## Quick Start

```bash
# Canonical control-plane cwd
export BEADS_DIR="$HOME/.beads-runtime/.beads"

# Start a job with cc-glm provider and explicit repo worktree
dx-runner start --beads bd-xxx --provider cc-glm --worktree /tmp/agents/bd-xxx/agent-skills --prompt-file /tmp/task.prompt

# Run the minimal two-reviewer quorum wrapper: Kimi K2.6 + DeepSeek V4 Pro via OpenCode.
dx-review run --beads bd-xxx --worktree /tmp/agents/bd-xxx/agent-skills --prompt-file /tmp/review.prompt --wait

# Run source-backed research wrapper and read merged summary first.
dx-research run --beads bd-xxx --worktree /tmp/agents/bd-xxx/agent-skills --topic "compare option A vs B" --depth deep --wait
dx-research summarize --beads bd-xxx

# Check job status
dx-runner status

# Check specific job health
dx-runner check --beads bd-xxx

# Generate report
dx-runner report --beads bd-xxx --format json

# Coordinate Beads state via wrapper
bdx show bd-xxx --json
```

## Command Reference

### start

Launch a job with specified provider:

```bash
dx-runner start --beads <id> --provider <name> --prompt-file <path> [options]

Options:
  --worktree <path>     Worktree path (must be under /tmp/agents or allowed prefix)
  --repo <name>         Repository name
  --profile <name>      Load profile from configs/dx-runner-profiles/<name>.yaml (bd-8wdg.1)
  --pty                 Use PTY for output capture
  --required-baseline <sha>  Enforce baseline gate before dispatch
  --allow-model-override    Allow OPENCODE_MODEL env override (bd-8wdg.2)
```

Operator contract:
- Run control-plane commands with `BEADS_DIR=~/.beads-runtime/.beads` from a non-app directory.
- Pass `--worktree /tmp/agents/<beads>/<repo>` explicitly for mutating jobs.
- Use `DX_RUNNER_DEFAULT_WORKTREE` only as fallback for legacy wrappers or previously recorded runs.
- Use `bdx` for Beads coordination around runs. Raw `bd` is for local diagnostics/bootstrap/path-sensitive operations.

### status

Show status of jobs:

```bash
dx-runner status [--beads <id>] [--json]
```

### prune

Prune stale/ghost PID records (including invalid/dead PIDs):

```bash
dx-runner prune [--beads <id>] [--json]
```

### check

Check single job health (exit codes indicate state):

```bash
dx-runner check --beads <id> [--json] [--stall-minutes <n>]

Exit Codes:
  0 = healthy or completed
  2 = stalled
  3 = error/blocked
```

### stop

Stop a running job:

```bash
dx-runner stop --beads <id>
```

### restart

Restart a job (preserves metadata, rotates logs):

```bash
dx-runner restart --beads <id>
```

### watchdog

Run watchdog loop for monitoring:

```bash
dx-runner watchdog [--interval <sec>] [--max-retries <n>]
```

### report

Generate job report:

```bash
dx-runner report --beads <id> [--format json|markdown]
```

### preflight

Run preflight checks:

```bash
dx-runner preflight [--provider <name>]
dx-runner preflight --profile opencode-go-kimi-review
```

### probe

Test provider/model availability:

```bash
dx-runner probe --provider <name> [--model <id>]
dx-runner probe --provider claude-code --model opus
```

### profiles (bd-8wdg.1)

List available profiles:

```bash
dx-runner profiles
```

### scope-gate (bd-8wdg.5)

Evaluate scope constraints:

```bash
dx-runner scope-gate --allowed-paths-file <path> [--mutation-budget <n>]
```

### evidence-gate (bd-8wdg.6)

Evaluate evidence requirements:

```bash
dx-runner evidence-gate --signoff-file <path>
```

### Governance Gates

```bash
# Baseline gate: verify runtime commit meets minimum
dx-runner baseline-gate --worktree <path> --required-baseline <sha>

# Integrity gate: verify reported commit exists
dx-runner integrity-gate --worktree <path> --reported-commit <sha>

# Feature-key gate: verify commits have required trailer
dx-runner feature-key-gate --worktree <path> --feature-key <bd-id>
```

### Workspace-First Gate (bd-kuhj.3)

`dx-runner` enforces workspace-first isolation by rejecting canonical repo paths:

**Allowed mutating paths:**
- `/tmp/agents/*`
- `/tmp/dx-runner/*`
- `/tmp/dxbench/*`
- `$HOME/agent-skills` (only for non-mutating read operations)

**Forbidden paths** (exit code 22, reason `canonical_worktree_forbidden`):
- `$HOME/agent-skills`
- `$HOME/prime-radiant-ai`
- `$HOME/affordabot`
- `$HOME/llm-common`

**Example rejection:**
```
reason_code=canonical_worktree_forbidden
rejected_path=$HOME/agent-skills
policy=workspace_first_v86
remedy=dx-worktree create bd-xxx agent-skills
ERROR: Mutating execution forbidden in canonical repo
Canonical repos are clean mirrors. Use: dx-worktree create bd-xxx agent-skills
```

**Normal operations still work** in canonical repos:
- `git fetch`, `git pull --ff-only`
- `railway status`, `railway run`, `railway shell`
- Loading skills from `~/agent-skills`

## Providers

### cc-glm (Reliability Backstop)

Z.ai/GLM wrapper lane using `cc-glm-headless.sh` and proven patterns from `cc-glm-job.sh`. This is not native Claude Code provider support.

```bash
dx-runner start --beads bd-xxx --provider cc-glm --prompt-file /tmp/task.prompt
```

**Auth resolution order:**
1. `CC_GLM_AUTH_TOKEN` - Direct token
2. `CC_GLM_TOKEN_FILE` - Path to token file
3. `ZAI_API_KEY` - Plain or op:// reference
4. `CC_GLM_OP_URI` - Explicit op:// reference
5. Default: `op://dev/Agent-Secrets-Production/ZAI_API_KEY`

### opencode (Primary Throughput)

OpenCode headless. Includes reliability fixes for:
- **bd-cbsb.15**: Capability preflight with strict canonical model enforcement
- **bd-cbsb.16**: Permission handling (worktree-only)
- **bd-cbsb.17**: No-op detection
- **bd-cbsb.18**: beads-mcp dependency check

```bash
dx-runner start --beads bd-xxx --provider opencode --prompt-file /tmp/task.prompt
```

**Model policy:**
- Direct opencode dispatch default: `zhipuai/glm-5.1`
- For implementation throughput, if unavailable: fail fast and dispatch via an available fallback provider
- For `dx-review`, profile-pinned OpenCode runs both default review lanes:
  `opencode-go/kimi-k2.6` and `opencode-go/deepseek-v4-pro`

### claude-code (Explicit Non-Default Lane)

Native Anthropic Claude Code CLI in headless prompt mode. Use this only for explicit non-default work that needs Claude Code Opus; it is not part of the default `dx-review` quorum.

```bash
dx-runner start --beads bd-xxx.claude --profile claude-code-review --worktree /tmp/agents/bd-xxx/repo --prompt-file /tmp/review.prompt
```

**Model policy:**
- Review/default required: `opus`
- Preflight checks `claude --print`, model availability, and non-interactive auth before launch
- Concurrency default: one native Claude Code review job per host

### gemini (Operational Lane)

Google Gemini CLI with detached launcher hardening:
- collision-safe launcher temp file creation (macOS/Linux)
- real child PID tracking (not short-lived wrapper PID)
- completion monitor + finalize `rc` grace window before no-rc classification
- auth policy: OAuth session via `gemini login` is the only canonical route (API-key env vars are not accepted by preflight)

```bash
dx-runner start --beads bd-xxx --provider gemini --prompt-file /tmp/task.prompt
```

Operator expectations for Gemini finalization:
- normal completion: `state=exited_ok`, `reason_code=process_exit_with_rc|outcome_exit_0`
- failure completion: `state=exited_err`, non-zero `exit_code` in outcome/report
- if `reason_code=monitor_no_rc_file` or `late_finalize_no_rc`, treat as runner lifecycle defect and escalate

## Profile System (bd-8wdg.1)

Profiles provide pre-configured settings for common workflows:

```bash
# Use production profile (strict governance)
dx-runner start --beads bd-xxx --profile opencode-prod --prompt-file /tmp/task.prompt

# Use default dx-review profiles directly
dx-runner start --beads bd-xxx.kimi --profile opencode-go-kimi-review --prompt-file /tmp/review.prompt --worktree /tmp/agents/bd-xxx/repo

dx-runner start --beads bd-xxx.deepseek --profile opencode-go-deepseek-review --prompt-file /tmp/review.prompt --worktree /tmp/agents/bd-xxx/repo

# List available profiles
dx-runner profiles
```

### Available Profiles

| Profile | Provider | Description |
|---------|----------|-------------|
| `opencode-prod` | opencode | Production: strict governance, canonical model only |
| `opencode-go-kimi-review` | opencode | Review: `opencode-go/kimi-k2.6` |
| `opencode-go-deepseek-review` | opencode | Review: `opencode-go/deepseek-v4-pro` |
| `opencode-review` | opencode | Compatibility alias for `opencode-go/kimi-k2.6` |
| `cc-glm-review` | cc-glm | Legacy/manual review profile; not part of default `dx-review` |
| `claude-code-review` | claude-code | Explicit non-default review profile, `opus` |
| `cc-glm-fallback` | cc-glm | Reliability backstop for critical waves |
| `gemini-burst` | gemini | Burst capacity with relaxed constraints |
| `dev` | opencode | Development: permissive, allows model override |

### Profile File Structure

```yaml
# configs/dx-runner-profiles/opencode-prod.yaml
provider: opencode
description: "Production profile with strict governance"
settings:
  allow_model_override: false
  required_baseline: null
  mutation_budget: null
  scope_paths: []
  evidence_signoff: false
```

Profile priority: CLI flags > profile settings > defaults

## Model Drift Blocking (bd-8wdg.2)

OpenCode adapter enforces its active profile model by default. Direct `--provider opencode` dispatch uses `zhipuai/glm-5.1`; `dx-review` profiles pin `opencode-go/kimi-k2.6` and `opencode-go/deepseek-v4-pro`. The `OPENCODE_MODEL` environment variable is **ignored** by default.

### Override Policy

```bash
# Blocked (default): OPENCODE_MODEL is ignored
OPENCODE_MODEL=some-other-model dx-runner start --beads bd-xxx --provider opencode ...

# Allowed via flag
dx-runner start --beads bd-xxx --provider opencode --allow-model-override ...

# Allowed via env
DX_RUNNER_ALLOW_MODEL_OVERRIDE=1 dx-runner start --beads bd-xxx --provider opencode ...

# Allowed via profile (dev profile has allow_model_override: true)
dx-runner start --beads bd-xxx --profile dev ...
```

When blocked, the job fails preflight with:
```
[opencode-adapter] BLOCKED model override attempt: OPENCODE_MODEL=<value> (override not allowed)
```

This prevents silent model drift where operators accidentally use non-canonical models.

## Health States

| State | Meaning | Action |
|-------|---------|--------|
| `launching` | Started, awaiting first output | Wait |
| `slow_start` (bd-8wdg.10) | Within grace period, no output yet | Wait (grace period) |
| `waiting_first_output` | CPU progress, no output past threshold | Monitor |
| `silent_mutation` | Worktree changed, no log output | Check worktree |
| `healthy` | Process running with activity | None |
| `stalled` | No progress for N minutes | Restart |
| `stopped` (bd-8wdg.3) | Manual stop via `dx-runner stop` | Review |
| `no_op` | No heartbeat/mutation (bd-cbsb.17) | Investigate |
| `no_op_success` (bd-8wdg.9) | Exit 0 but no mutations | Redispatch with guardrails |
| `exited_ok` | Exited with code 0 | Review output |
| `exited_err` | Exited with non-zero | Check logs |
| `blocked` | Max retries exhausted | Manual intervention |
| `missing` | No metadata found | Investigate |

### Startup-Aware Health (bd-8wdg.10)

Jobs in initial startup phase use `slow_start` state with configurable grace periods:

```bash
# Default grace: 60 seconds
dx-runner start --beads bd-xxx --provider opencode ...

# Custom grace period
DX_RUNNER_SLOW_START_GRACE=120 dx-runner start ...
```

Transition: `slow_start` → `healthy` (on first output) or `slow_start` → `waiting_first_output` (grace expired)

### Truthful Outcome Semantics (bd-8wdg.3)

Health checks now use outcome `reason_code` when available, avoiding false-positive "healthy" classifications:

- `stopped`: Set when job stopped via `dx-runner stop`
- Outcome reason codes take precedence over process-alive heuristics

Failure taxonomy notes:
- `process_exit_with_rc`: process exited and runner captured `rc` deterministically
- `monitor_no_rc_file`: monitor could not find `rc` file within grace window (unexpected in healthy lane)
- `late_finalize_no_rc`: late finalize path could not find `rc` file within grace window (unexpected in healthy lane)

## Job Artifacts

```
/tmp/dx-runner/<provider>/
├── <beads>.pid         # Process ID
├── <beads>.log         # Current output log
├── <beads>.log.<n>     # Rotated logs
├── <beads>.meta        # Metadata (provider, worktree, retries)
├── <beads>.outcome     # Final outcome
├── <beads>.rc          # Captured provider exit code
├── <beads>.contract    # Runtime contract
├── <beads>.mutation    # Mutation marker
├── <beads>.heartbeat   # Heartbeat tracking
└── <beads>.monitor.pid # Completion monitor PID
```

## Governance Features

### Permission Gate (bd-cbsb.16)

Only worktree paths are allowed:

```
Allowed prefixes:
- /tmp/agents
- /tmp/dx-runner
- $HOME/agent-skills
```

Non-worktree paths are rejected with exit code 22.
If no safe worktree can be inferred (for example launching from `$HOME` without
`--worktree` and no prior beads metadata), runner exits with:

```
reason_code=worktree_missing
```

### No-op Detection (bd-cbsb.17)

Tracks heartbeat (tool invocations, mutations, log output). If no heartbeat for 5 minutes with no mutations, job is classified as `no_op`.

### Capability Preflight (bd-cbsb.15)

OpenCode adapter:
1. Checks preferred model availability
2. Falls back through chain if unavailable
3. Records selected model and failure reason
4. Probes model health with timeout

### beads-mcp Check (bd-cbsb.18)

OpenCode adapter warns if beads-mcp not found:
```
beads-mcp binary: MISSING (optional - Beads context degraded)
```

### Scope Guard (bd-8wdg.5)

Enforces filesystem scope constraints before job dispatch:

```bash
# Create allowed paths file
echo -e "/tmp/agents/bd-xxx\n/tmp/dx-runner" > /tmp/scope.txt

# Evaluate scope gate
dx-runner scope-gate --allowed-paths-file /tmp/scope.txt --mutation-budget 50

# Returns exit 0 if in scope, non-zero if out of scope
```

Options:
- `--allowed-paths-file`: File with allowed path prefixes (one per line)
- `--mutation-budget`: Maximum allowed file mutations

### Evidence Gate (bd-8wdg.6)

Verifies required signoffs/artifacts before considering job complete:

```bash
# Check for signoff file
dx-runner evidence-gate --signoff-file /tmp/agents/bd-xxx/SIGNOFF.md

# Returns exit 0 if evidence present, non-zero if missing
```

Options:
- `--signoff-file`: Path to required signoff/evidence file

### mise Trust Auto-Remediation (bd-8wdg.11)

OpenCode adapter automatically attempts to trust mise if untrusted:

```bash
# During start, if mise is untrusted:
# 1. Auto-run: mise trust (in worktree)
# 2. Report status in preflight
# 3. Continue if trust succeeds
```

Preflight output shows:
```
mise trust: UNTRUSTED → TRUSTED (auto-remediated)
```

Or if remediation fails:
```
mise trust: UNTRUSTED
  WARN_CODE=opencode_mise_untrusted severity=warn action=run_mise_trust_in_worktree
```

Preflight noise policy:
- `opencode_mise_untrusted` is emitted only when a concrete `.mise.toml` target
  is in scope.
- Otherwise preflight reports:
  - `mise trust: N/A (no .mise target)`

## Migration from Legacy Tools

| Legacy Command | dx-runner Equivalent |
|----------------|---------------------|
| `cc-glm-job.sh start --beads bd-xxx --prompt-file /tmp/p.prompt` | `dx-runner start --provider cc-glm --beads bd-xxx --prompt-file /tmp/p.prompt` |
| `cc-glm-job.sh status` | `dx-runner status` |
| `cc-glm-job.sh check --beads bd-xxx` | `dx-runner check --beads bd-xxx` |
| `dx-dispatch epyc12 "task"` | `dx-runner start --provider opencode --beads <id> --prompt-file <path>` |
| `dx-dispatch --list` | `dx-runner status` |

## JSON Output Schema

### status --json

```json
{
  "generated_at": "2026-02-18T12:00:00Z",
  "jobs": [
    {
      "beads": "bd-xxx",
      "provider": "cc-glm",
      "pid": "12345",
      "state": "healthy",
      "reason_code": "cpu_progress",
      "elapsed": "5m",
      "log_bytes": 1024,
      "mutation_count": 3,
      "retry_count": 0,
      "outcome": "-"
    }
  ]
}
```

### report --format json

```json
{
  "beads": "bd-xxx",
  "provider": "opencode",
  "state": "exited_ok",
  "reason_code": "outcome_exit_0",
  "started_at": "2026-02-18T12:00:00Z",
  "duration_sec": "300",
  "retries": 0,
  "exit_code": "0",
  "outcome_state": "success",
  "selected_model": "zhipuai/glm-5.1",
  "fallback_reason": "none",
  "execution_mode": "detached",
  "worktree": "/tmp/agents/bd-xxx/repo",
  "mutations": 5,
  "log_bytes": 2048,
  "cpu_time_sec": 120,
  "pid_age_sec": 310
}
```

## Normalized Telemetry Fields

All providers emit the following normalized fields in outcome files:

| Field | Description |
|-------|-------------|
| `provider` | Provider name (cc-glm, opencode, claude-code, gemini) |
| `selected_model` | Model selected for execution |
| `reason_code` | Reason for state transition |
| `fallback_reason` | If fallback occurred, why |
| `state` | Final state (success, failed, killed, no_op) |
| `execution_mode` | How process was launched (detached, pty-detached, detached-script, etc.) |
| `started_at` | ISO 8601 timestamp when job started |
| `completed_at` | ISO 8601 timestamp when job completed |
| `exit_code` | Process exit code |

## Failure Taxonomy

| Exit Code | Reason | Action |
|-----------|--------|--------|
| 0 | Success | None |
| 1 | General error | Check logs |
| 2 | Job stalled | Restart or investigate |
| 3 | Job exited with error | Check logs |
| 10 | Auth resolution failed | Configure auth |
| 11 | Token file error | Fix token file |
| 20 | Provider not found | Check adapter |
| 21 | Preflight failed | Fix preflight issues |
| 22 | Permission denied | Use worktree path |
| 23 | No-op detected | Investigate job |

## dx-wave Wrapper (bd-8wdg.7)

`dx-wave` is a safe operator wrapper with profile-first defaults:

```bash
# Uses opencode-prod profile by default
dx-wave start --beads bd-xxx --prompt-file /tmp/task.prompt

# Explicit profile selection
dx-wave start --beads bd-xxx --profile cc-glm-fallback --prompt-file /tmp/task.prompt

# List profiles
dx-wave profiles

# Show help
dx-wave --help

# Compatibility/operator batch entrypoint
dx-wave batch-start --items bd-a,bd-b --prompt-file /tmp/task.prompt
```

Key differences from direct `dx-runner`:
- Requires `--profile` (defaults to `opencode-prod`)
- Enforces profile-first workflow
- Simplified interface for wave operators
- Includes deterministic compatibility batch fallback:
  - Emits `WARN_CODE=dx_batch_unavailable_fallback_runner`
  - Falls back to per-item `dx-runner start` dispatch

## Related

- ADR: `docs/adr/ADR-DX-RUNNER.md`
- Adapters: `scripts/adapters/*.sh`
- Tests: `scripts/test-dx-runner.sh`
