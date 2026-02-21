---
name: dx-runner
description: |
  Canonical unified runner for multi-provider dispatch with shared governance.
  Routes to cc-glm, opencode, or gemini providers with unified preflight, gates, and failure taxonomy.
  Use when dispatching agent tasks, running headless jobs, or managing parallel agent sessions.
tags: [workflow, dispatch, governance, multi-provider, automation]
allowed-tools:
  - Bash
---

# dx-runner: Unified Multi-Provider Dispatch Runner

## Overview

`dx-runner` is the **canonical entrypoint** for all agent dispatch. It provides:

- **Single command surface**: start/status/check/restart/stop/watchdog/report/preflight
- **Multi-provider support**: cc-glm (reliability backstop), opencode (primary throughput), gemini (future)
- **Unified governance**: preflight, permission gates, no-op detection, baseline/integrity/feature-key gates
- **Deterministic outputs**: Machine-readable JSON with stable schemas

OpenCode behavior in this skill is grounded in official docs and live CLI help:
- [OpenCode CLI docs](https://opencode.ai/docs/cli/)
- [OpenCode server docs](https://opencode.ai/docs/server/)
- `opencode run --help` on the target host (for exact supported flags)

## When To Use

- Dispatching any agent task (replaces cc-glm-job.sh, dx-dispatch)
- Running headless agent sessions
- Managing parallel agent jobs
- Checking job health with governance gates
- Generating job reports

## Quick Start

```bash
# Start a job with cc-glm provider
dx-runner start --beads bd-xxx --provider cc-glm --prompt-file /tmp/task.prompt

# Check job status
dx-runner status

# Check specific job health
dx-runner check --beads bd-xxx

# Generate report
dx-runner report --beads bd-xxx --format json
```

## Command Reference

### start

Launch a job with specified provider:

```bash
dx-runner start --beads <id> --provider <name> --prompt-file <path> [options]

Options:
  --worktree <path>     Worktree path (must be under /tmp/agents or allowed prefix)
  --repo <name>         Repository name
  --pty                 Use PTY for output capture
  --required-baseline <sha>  Enforce baseline gate before dispatch
```

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
```

### probe

Test provider/model availability:

```bash
dx-runner probe --provider <name> [--model <id>]
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

## Providers

### cc-glm (Reliability Backstop)

Claude via Z.ai. Proven patterns from cc-glm-job.sh.

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
- Required: `zhipuai-coding-plan/glm-5`
- If unavailable: fail fast and dispatch via `cc-glm` or `gemini`

### gemini (Operational Lane)

Google Gemini CLI with detached launcher hardening:
- collision-safe launcher temp file creation (macOS/Linux)
- real child PID tracking (not short-lived wrapper PID)
- completion monitor + finalize `rc` grace window before no-rc classification

```bash
dx-runner start --beads bd-xxx --provider gemini --prompt-file /tmp/task.prompt
```

Operator expectations for Gemini finalization:
- normal completion: `state=exited_ok`, `reason_code=process_exit_with_rc|outcome_exit_0`
- failure completion: `state=exited_err`, non-zero `exit_code` in outcome/report
- if `reason_code=monitor_no_rc_file` or `late_finalize_no_rc`, treat as runner lifecycle defect and escalate

## Health States

| State | Meaning | Action |
|-------|---------|--------|
| `launching` | Started, awaiting first output | Wait |
| `waiting_first_output` | CPU progress, no output past threshold | Monitor |
| `silent_mutation` | Worktree changed, no log output | Check worktree |
| `healthy` | Process running with activity | None |
| `stalled` | No progress for N minutes | Restart |
| `no_op` | No heartbeat/mutation (bd-cbsb.17) | Investigate |
| `exited_ok` | Exited with code 0 | Review output |
| `exited_err` | Exited with non-zero | Check logs |
| `blocked` | Max retries exhausted | Manual intervention |
| `missing` | No metadata found | Investigate |

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
  "provider": "cc-glm",
  "state": "exited_ok",
  "reason_code": "outcome_exit_0",
  "started_at": "2026-02-18T12:00:00Z",
  "duration_sec": "300",
  "retries": 0,
  "exit_code": "0",
  "outcome_state": "success",
  "selected_model": "glm-5",
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
| `provider` | Provider name (cc-glm, opencode, gemini) |
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

## Related

- ADR: `docs/adr/ADR-DX-RUNNER.md`
- Adapters: `scripts/adapters/*.sh`
- Tests: `scripts/test-dx-runner.sh`
