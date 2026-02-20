# Multi-Provider Soak Validation

Deterministic 6-stream multi-provider soak validation for tech-lead signoff.

## Overview

This validation runner executes 6 parallel jobs (2 per provider: opencode, cc-glm, gemini) across two consecutive clean rounds, producing machine-readable JSON and human-readable Markdown artifacts.

## Requirements

- Two consecutive clean rounds (100% success rate per round)
- No failures across any provider
- OpenCode provider uses `zhipuai-coding-plan/glm-5` (no `zai-coding-plan` fallback)

## Quick Start

```bash
# Run validation (dry-run for testing)
python3 scripts/validation/multi_provider_soak.py --dry-run

# Run actual validation
python3 scripts/validation/multi_provider_soak.py

# Run with custom options
python3 scripts/validation/multi_provider_soak.py \
  --rounds 2 \
  --parallel 6 \
  --timeout-sec 300
```

## Command Reference

### Required

No required arguments - uses sensible defaults.

### Optional

| Flag | Default | Description |
|------|---------|-------------|
| `--dry-run` | false | Simulate without actual dispatch |
| `--rounds N` | 2 | Number of consecutive rounds |
| `--parallel N` | 6 | Parallel job count |
| `--timeout-sec N` | 300 | Job timeout in seconds |
| `--worktree PATH` | cwd | Worktree path for jobs |
| `--run-id ID` | auto | Run ID (auto-generated if not set) |
| `--output-dir PATH` | artifacts/multi-provider-soak | Output directory |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Validation passed (all rounds clean) |
| 1 | Validation failed |
| 21 | Preflight failed |

## Artifacts

Each run produces two timestamped artifacts in `artifacts/multi-provider-soak/`:

### JSON (`{run-id}.json`)

Machine-readable summary with:
- Per-job metrics: status, latency_ms, completion, reason_code, selected_model, retries, outcome_state
- Per-provider summary: total, passed, failed, latency_ms_mean, latency_ms_p50
- Round aggregation: pass_rate, duration_sec
- Overall result: passed, all_clean

### Markdown (`{run-id}.md`)

Human-readable report with:
- Summary table (total jobs, passed, failed, pass rate)
- Provider summary table
- Per-round job details
- Pass/fail gate explanation

## Data Structures

### JobResult Fields

| Field | Type | Description |
|-------|------|-------------|
| success | bool | Job completed successfully |
| status | str | Terminal state (exited_ok, exited_err, stalled, etc.) |
| reason_code | str? | Failure classification code |
| selected_model | str? | Model actually used |
| latency_ms | int? | End-to-end latency in milliseconds |
| completion | bool | Job reached terminal state |
| retries | int | Number of retry attempts |
| outcome_state | str | Final outcome classification |

### Failure Reason Codes

| Code | Description |
|------|-------------|
| model_unavailable | Requested model not available |
| auth_error | Authentication/quota issue |
| permission_denied | Worktree permission issue |
| start_failed | Job dispatch failed |
| wait_timeout | Job exceeded timeout |
| executor_exception | Unhandled exception |

## Provider Configuration

### OpenCode

- Canonical model: `zhipuai-coding-plan/glm-5`
- Override via `OPENCODE_MODEL` environment variable

### cc-glm

- Default model: `glm-5`
- Override via `CC_GLM_MODEL` environment variable

### Gemini

- Default model: `gemini-3-flash-preview`
- Override via `GEMINI_MODEL` environment variable

## Integration with dx-runner

This validation runner uses `dx-runner` as the canonical command surface:

1. **Preflight**: Runs `dx-runner preflight --provider opencode`
2. **Job Dispatch**: Uses `dx-runner start --provider <name>`
3. **Job Monitoring**: Uses `dx-runner check --beads <id>`
4. **Outcome Collection**: Uses `dx-runner report --beads <id>`

## Testing

Run unit tests:

```bash
python3 scripts/validation/test_multi_provider_soak.py
```

## Example Output

```
=== Multi-Provider Soak Validation ===
Run ID: soak-20260220T013446Z
Rounds: 2
Providers: opencode, cc-glm, gemini (2 jobs each)

--- Round 1/2 ---
Round 1: PASSED (100.0% pass rate)
  [opencode] echo_ok: OK (success)
  [opencode] echo_ready: OK (success)
  [cc-glm] echo_ok: OK (success)
  [cc-glm] echo_ready: OK (success)
  [gemini] echo_ok: OK (success)
  [gemini] echo_ready: OK (success)

--- Round 2/2 ---
Round 2: PASSED (100.0% pass rate)
  [opencode] echo_ok: OK (success)
  [opencode] echo_ready: OK (success)
  [cc-glm] echo_ok: OK (success)
  [cc-glm] echo_ready: OK (success)
  [gemini] echo_ok: OK (success)
  [gemini] echo_ready: OK (success)

=== Validation Complete ===
Status: PASSED
All Clean: Yes
Total: 12/12 passed
Duration: 120.5s

Artifacts:
  JSON: artifacts/multi-provider-soak/soak-20260220T013446Z.json
  Markdown: artifacts/multi-provider-soak/soak-20260220T013446Z.md
```
