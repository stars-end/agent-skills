# DX Runner Runbook (V1.3)

Wave-based parallel dispatch with OpenCode (GLM-5) + Gemini.

## Quick Reference

```bash
# Preflight checks
dx-runner preflight --provider opencode
dx-runner preflight --provider gemini

# Beads gate (before wave)
dx-runner beads-gate --repo /path/to/repo [--probe-id bd-xxx] [--write-probe]

# Start parallel jobs
dx-runner start --beads bd-xxx --provider opencode --prompt-file /tmp/p.prompt
dx-runner start --beads bd-yyy --provider gemini --prompt-file /tmp/q.prompt

# Monitor
dx-runner status [--json]
dx-runner status --recent 10
dx-runner check --beads bd-xxx [--json]

# Cleanup
dx-runner prune
dx-runner stop --beads bd-xxx
dx-runner finalize --beads bd-xxx --reason stalled --exit-code 1
```

## Preflight / Beads Gate

### 1. Provider Preflight

Run before wave dispatch to verify provider availability:

```bash
# OpenCode (canonical + allowlisted GLM-5 variants)
dx-runner preflight --provider opencode

# Gemini
dx-runner preflight --provider gemini
```

**Pass criteria:**
- Binary found
- API credentials valid
- Canonical/allowlisted model available (OpenCode defaults: `zhipuai-coding-plan/glm-5`, `zai-coding-plan/glm-5`)

### 2. Beads Integrity Gate

Run before wave to verify Beads DB connectivity:

```bash
# Basic connectivity check
dx-runner beads-gate --repo /path/to/worktree

# With probe ID for repo-id validation
dx-runner beads-gate --repo /path/to/worktree --probe-id bd-xxx

# With write probe (tests write permissions)
dx-runner beads-gate --repo /path/to/worktree --probe-id bd-xxx --write-probe
```

By default, the gate also enforces external Beads repo governance:
- Repo path: `~/bd` (override with `BEADS_REPO_PATH`)
- Origin remote contains: `stars-end/bd` (override with `BEADS_REPO_REMOTE_SUBSTR`)

**Exit code 24** = Beads gate failed. See reason_code in output.

### Beads Gate Reason Codes

| Code | Meaning | Action |
|------|---------|--------|
| `beads_ok` | Gate passed | Proceed with dispatch |
| `beads_unavailable` | `bd` CLI not found | Install beads CLI |
| `beads_external_repo_missing` | External repo missing at `~/bd` | Clone/sync `~/bd` |
| `beads_external_remote_mismatch` | External repo origin is not `stars-end/bd` | Fix `~/bd` origin URL |
| `beads_db_error` | DB connectivity failed | Check DB URL, network |
| `beads_repo_mismatch` | Repo ID mismatch | Reinitialize repo binding |
| `beads_write_blocked` | Write probe failed | Check DB permissions |
| `beads_probe_not_found` | Probe ID not found | Use valid issue ID |

## Parallel Launch Examples

### OpenCode + Gemini Mixed Wave

```bash
# Wave with 4 parallel jobs: 2 OpenCode, 2 Gemini
dx-runner start --beads bd-task1 --provider opencode --prompt-file /tmp/task1.prompt &
dx-runner start --beads bd-task2 --provider opencode --prompt-file /tmp/task2.prompt &
dx-runner start --beads bd-task3 --provider gemini --prompt-file /tmp/task3.prompt &
dx-runner start --beads bd-task4 --provider gemini --prompt-file /tmp/task4.prompt &
wait
```

### Check All Jobs

```bash
# JSON status for all
dx-runner status --json | jq '.jobs[] | {beads, state, reason_code}'

# Recent completed jobs
dx-runner status --recent 10 --json

# Wait for completion
for id in bd-task1 bd-task2 bd-task3 bd-task4; do
    while true; do
        state=$(dx-runner check --beads "$id" --json 2>/dev/null | jq -r '.state')
        [[ "$state" == "exited_ok" || "$state" == "exited_err" ]] && break
        sleep 5
    done
done
```

## Failure Taxonomy

### OpenCode Failure Codes

| Code | Meaning | Fallback |
|------|---------|----------|
| `opencode_model_unavailable` | GLM-5 not in available models | Use gemini or cc-glm |
| `opencode_model_unsupported` | Requested non-canonical model | Must use GLM-5 |
| `opencode_binary_missing` | CLI not installed | Install opencode |
| `opencode_auth_blocked` | Auth/quota issue | Check API key, quota |
| `opencode_rate_limited` | Runtime rate/quota throttling | Backoff retry or switch provider |

### Gemini Failure Codes

| Code | Meaning | Action |
|------|---------|--------|
| `gemini_binary_missing` | CLI not installed | Install gemini CLI |
| `gemini_auth_missing` | No API key set | Set GEMINI_API_KEY |
| `gemini_auth_blocked` | Invalid API key | Check credentials |
| `gemini_capacity_exhausted` | Capacity/429 exhaustion | Backoff retry or switch to opencode/cc-glm |

### Health States

| State | Meaning | Action |
|-------|---------|--------|
| `launching` | Just started, no output yet | Wait |
| `healthy` | Progress detected | Monitor |
| `stalled` | No progress for stall threshold | Restart or investigate |
| `no_op` | No heartbeat, no mutation | Likely blocked |
| `exited_ok` | Exit code 0 | Success |
| `exited_err` | Non-zero exit | Check logs |
| `blocked` | Max retries reached | Manual intervention |

## Outcome Metadata

Every terminated job has an outcome file at `/tmp/dx-runner/<provider>/<beads>.outcome`:

```
beads=bd-xxx
provider=opencode
run_id=20260219120000
exit_code=0
state=success
reason_code=process_exit
completed_at=2026-02-19T12:05:00Z
duration_sec=300
retries=0
selected_model=zhipuai-coding-plan/glm-5
fallback_reason=none
run_instance=20260219120000-opencode-12345
host=epyc12
cwd=/tmp/agents/bd-xga8.14.2/agent-skills
worktree=/tmp/agents/bd-xga8.14.2/prime-radiant-ai
```

### Report Command

```bash
dx-runner report --beads bd-xxx --format json
dx-runner report --beads bd-xxx --format markdown
```

Provider switch safety:
- Reusing the same `beads` across providers is supported.
- Runner resolves `status/check/report` to the latest provider instance for that beads id.
- Metadata includes `provider_switch_from`, `run_instance`, `host`, `cwd`, and `worktree` for auditability.

## Force Finalization

Use when a job is stuck and needs manual termination:

```bash
# Finalize with default reason
dx-runner finalize --beads bd-xxx

# Finalize with custom reason and exit code
dx-runner finalize --beads bd-xxx --reason stalled --exit-code 1
```

## Stale/Ghost Cleanup

Prune removes dead/invalid PID records:

```bash
# Prune specific job
dx-runner prune --beads bd-xxx

# Prune all stale jobs
dx-runner prune
```

Prune handles:
- Invalid PID files (non-numeric)
- Dead processes (exited without outcome)
- Ghost entries from crashed runs

## When to Fallback to cc-glm

Use cc-glm provider when:

1. **OpenCode GLM-5 unavailable** (reason_code=`opencode_model_unavailable`)
2. **Auth/quota blocked** on both opencode and gemini
3. **Critical wave** requiring reliability backstop

```bash
dx-runner start --beads bd-xxx --provider cc-glm --prompt-file /tmp/p.prompt
```

## Watchdog Mode

Automatic monitoring and restart:

```bash
# Watchdog with 60s interval, max 1 retry
dx-runner watchdog --interval 60 --max-retries 1
```

Watchdog actions:
- Detects `stalled` or `no_op` states
- Force-finalizes jobs exceeding timeout thresholds
- Sets `blocked=true` after max retries

### Timeout Configuration

```bash
# Environment variables
export DX_RUNNER_MAX_RUNTIME_MINUTES=120
export DX_RUNNER_NO_MUTATION_TIMEOUT_MINUTES=30
```

## Environment Variables

| Variable | Provider | Description |
|----------|----------|-------------|
| `OPENCODE_MODEL` | opencode | Override model (must be GLM-5) |
| `OPENCODE_CANONICAL_MODEL` | opencode | Canonical model to prefer |
| `OPENCODE_ALLOWED_MODELS` | opencode | Comma-separated allowed model list |
| `GEMINI_MODEL` | gemini | Override model (default: gemini-3-flash-preview) |
| `GEMINI_API_KEY` | gemini | API key |
| `GOOGLE_API_KEY` | gemini | Alternative API key |
| `DX_RUNNER_MAX_RUNTIME_MINUTES` | all | Max job runtime before force-finalize |
| `DX_RUNNER_NO_MUTATION_TIMEOUT_MINUTES` | all | No-mutation timeout |
| `BEADS_REPO_PATH` | all | External Beads repo path (default: `~/bd`) |
| `BEADS_REPO_REMOTE_SUBSTR` | all | Expected external repo origin substring (default: `stars-end/bd`) |
| `BEADS_FLUSH_STRICT` | commit hooks | `1` makes Beads JSONL flush failures blocking |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Job stalled |
| 3 | Job exited with error |
| 20 | Provider not found |
| 21 | Preflight failed |
| 22 | Permission denied |
| 23 | No-op detected |
| 24 | Beads gate failed |
| 25 | Model unavailable |
