# ADR: DX V8 Unified Dispatch (dx-runner)

## Status
**Status:** ACCEPTED  
**Date:** 2026-02-19  
**Epoch:** DX V8

## Context and Pain Points

Prior to DX V8, the agent dispatch landscape was fragmented across multiple independent execution planes:
- `cc-glm-job.sh`: Specialized for Claude dispatch via Z.ai with internal governance.
- `opencode` CLI: Direct interaction with OpenCode headless, lacking project-specific gates.
- `gemini` CLI: Newest provider with inconsistent logging and metadata formats.

This divergence created several critical pain points:
1. **Inconsistent Governance**: Preflight checks and permission gates (like worktree-only policy) were implemented unevenly.
2. **Observability Gaps**: Tracking job health, staleness, and outcomes required different tools for different providers.
3. **No-op Detection Failure**: Multiple instances of agents running without making progress (no-op) went undetected due to inconsistent heartbeat logic.
4. **Maintenance Overhead**: Security fixes or policy changes (e.g., beads-gate) had to be duplicated across scripts.

## Decision: Unified Runner (dx-runner)

We replace all provider-specific dispatch entrypoints with a single, canonical entrypoint: `dx-runner`. This runner implements a unified governance layer and delegates execution to provider-specific adapters.

### Contract Semantics

All operations follow a strict contract for consistency:

| Command | Semantic Description |
|---------|----------------------|
| `start` | **Execution Launch**: Performs unified preflight, permission checks, and baseline verification before delegating to the provider adapter. Sets up heartbeat and mutation monitoring. |
| `check` | **Health Verification**: Deterministically classifies job state. Exits with code 2 if stalled/no-op, 3 if failed. |
| `status` | **Observability**: Provides a unified table of all active and recent jobs across all providers. Supports `--json` for automation. |
| `report` | **Artifact Aggregation**: Generates a consolidated report of job metadata, duration, and outcome. |
| `restart` | **Stateful Recovery**: Gracefully stops the existing job and restarts using original metadata, incrementing the retry counter. |
| `stop` | **Graceful Termination**: Signals the job and its monitor process to stop, ensuring an `outcome` file is generated. |
| `preflight` | **Capability Check**: Verified auth, model availability, and environment readiness for a specific provider or all providers. |
| `beads-gate` | **Integrity Check**: Verifies Beads DB connectivity and repo-to-issue binding to prevent cross-repo leakage. |
| `baseline-gate` | **Version Check**: Verifies that the runtime commit meets the required baseline SHA. |
| `integrity-gate` | **Commit Verification**: Verifies that the reported commit exists in the current branch history. |
| `feature-key-gate` | **Trailer Verification**: Verifies that all commits in the current range include the required `Feature-Key` trailer. |
| `finalize` | **Manual Recovery**: Forces finalization of a job, ensuring an outcome is recorded even if the process is stuck or missing. |
| `prune` | **Maintenance**: Cleans up stale job records and PID files for completed or dead processes. |
| `watchdog` | **Continuous Monitoring**: Orchestrates a loop of health checks and automated restarts across all active jobs. |

## Provider Policy

1. **Canonical Model Constraints**: 
   - Providers (especially OpenCode) MUST enforce strict canonical model usage (e.g., `zhipuai-coding-plan/glm-5`) to ensure result quality and reliability. 
   - If the preferred model is unavailable, the runner MUST fail-fast rather than silently falling back to a weaker model.
2. **Fail-Fast Behavior**: 
   - Preflight failures are blocking. 
   - Permission violations (non-worktree paths) are blocking (Exit 22).
   - No-op detection (no mutation + no log activity) triggers a fail-fast exit (Exit 23).

## Lifecycle/Outcome Artifacts Contract

All jobs managed by `dx-runner` produce a standardized set of artifacts in `/tmp/dx-runner/<provider>/`:

| File | Purpose |
|------|---------|
| `<beads>.pid` | Current PID of the detached job process. |
| `<beads>.log` | Combined stdout/stderr of the job. |
| `<beads>.meta` | Key-value pairs of job metadata (start time, worktree, model, etc.). |
| `<beads>.outcome` | Final result of the job (exit_code, state, duration, reason). |
| `<beads>.rc` | The raw exit code from the adapter process. |
| `<beads>.contract` | Sourced runtime parameters used for the dispatch. |
| `<beads>.heartbeat` | Last activity timestamp and type (log, mutation, tool). |
| `<beads>.mutation` | Tracking of file system changes in the worktree. |

## Operational Runbook Snippets

### Starting a Job
```bash
./scripts/dx-runner start 
  --beads bd-xga8.14 
  --provider opencode 
  --prompt-file /tmp/p.prompt 
  --worktree /tmp/agents/bd-xga8.14/agent-skills
```

### Checking Status
```bash
./scripts/dx-runner status --beads bd-xga8.14 --json
```

### Emergency Stop
```bash
./scripts/dx-runner stop --beads bd-xga8.14
```

### Health Check (Watchdog style)
```bash
./scripts/dx-runner check --beads bd-xga8.14 || echo "Job needs attention"
```

## Migration Plan + Compatibility Policy

1. **Shim Layer**: `dx-dispatch` and `cc-glm-job.sh` will be updated to act as shims that forward calls to `dx-runner`.
2. **Legacy Support**: Artifacts previously located in `/tmp/cc-glm/` will be symlinked or migrated to `/tmp/dx-runner/cc-glm/` to maintain compatibility with existing dashboards.
3. **Deprecation**: Direct usage of provider-specific scripts is deprecated as of DX V8.

## Risks and Follow-up Tasks

| Risk | Mitigation |
|------|------------|
| Single Point of Failure | `dx-runner` is a lean bash script with minimal dependencies; provider failures are isolated in adapters. |
| Monitoring Overhead | The monitor process is extremely lightweight (sleep-loop) and strictly detached from the job lifecycle. |
| Artifact Proliferation | `prune` command and automated cleanup logic in `status` prevent `/tmp` exhaustion. |

**Follow-up Tasks:**
- [ ] Implement `gemini` adapter with full contract parity.
- [ ] Integrate `dx-runner report` output into GitHub Actions PR comments.
- [ ] Enable `watchdog` systemd service for fleet-wide monitoring.
