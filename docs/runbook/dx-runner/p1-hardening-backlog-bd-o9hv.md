# dx-runner P1 Hardening Backlog (bd-o9hv)

Owner epic in Beads: `bd-o9hv`

This document is the implementation handoff for dx-runner platform hardening discovered during Fleet Sync dispatch (`bd-d8f4.9` on `epyc6`).

## Scope

- Runtime reliability and operator ergonomics for long-running dx-runner jobs.
- Deterministic JSON/monitoring contracts for single-host and cross-host orchestration.
- Skill/runtime contract alignment to prevent command drift.

## Non-goals

- No Fleet Sync architecture redesign.
- No provider switch away from OpenCode canonical lane.
- No changes to Beads topology.

## Why this exists

Observed gaps during live dispatch required ad-hoc loops and manual evidence assembly. The backlog below turns those into productized, deterministic commands and contracts.

## P1 Tasks

1. `bd-o9hv.1` — Add first-class monitor command
- Deliver: `dx-runner monitor --beads <id> --interval 600 [--json] [--out-file <path>]`
- Required cycle fields: `timestamp_utc`, `cycle`, `beads`, `provider`, `state`, `reason_code`, `log_bytes`, `mutation_count`, `pid_age_sec`
- Terminal exit states: `exited_ok`, `exited_err`, `stopped`, `blocked`, `missing`

2. `bd-o9hv.2` — Freshness/no-op guardrails in status/check/report
- Add stale progression reason-codes and thresholds.
- Ensure low-signal runs are not shown as indefinitely healthy.

3. `bd-o9hv.3` — Preflight warning taxonomy + strict mode
- Convert optional dependency warnings into stable warn/error codes with `next_action`.
- Add strict-mode escalation policy where required by lane/profile.

4. `bd-o9hv.7` — Bash interpreter portability gate
- Ensure macOS Bash 3.2 paths fail predictably with machine-readable remediation.
- Ensure wrappers use supported bash where present.

5. `bd-o9hv.4` — Skill/runtime alignment
- Reconcile `extended/dx-runner/SKILL.md` with live CLI behavior.
- Include canonical 600s monitoring and handoff examples.

6. `bd-o9hv.5` — One-command observability bundle
- Add deterministic bundle command for status/check/report/log tail + metadata.
- Output ready for Beads notes and PR comments.

7. `bd-o9hv.6` — Cross-host monitoring contract
- Add host-scoped JSON contract fields to avoid identity collision/stale false-green in fleet aggregation.

## Dependency order

Execution sequence:

1. `bd-o9hv.1`
2. `bd-o9hv.2`
3. `bd-o9hv.3`
4. `bd-o9hv.7`
5. `bd-o9hv.4`
6. `bd-o9hv.5`
7. `bd-o9hv.6`

Graph summary:

- `bd-o9hv.1/.2/.3/.7` block `bd-o9hv.4`
- `bd-o9hv.1/.2` block `bd-o9hv.5`
- `bd-o9hv.1/.2/.3/.7` block `bd-o9hv.6`

## Affected files (expected)

- `scripts/dx-runner`
- `scripts/test-dx-runner.sh`
- `scripts/adapters/opencode-adapter.sh` (or provider-specific adapter used by preflight)
- `extended/dx-runner/SKILL.md`
- Optional wrapper docs under `docs/runbook/`

## Repro commands (baseline)

```bash
# Preflight warning surface
scripts/dx-runner preflight --provider opencode

# Health/status behavior
scripts/dx-runner status --beads <id> --json
scripts/dx-runner check --beads <id> --json
scripts/dx-runner report --beads <id> --format json

# Current ad-hoc monitor pattern (to be replaced by monitor subcommand)
while true; do scripts/dx-runner status --beads <id> --json; sleep 600; done
```

## Acceptance gates per task

Each subtask must provide:

- deterministic CLI contract and JSON schema updates
- reproducible validation command(s)
- evidence artifact path under `/tmp/bd-o9hv-evidence/<subtask-id>/`
- docs update for operator action path (`next_action`, exit semantics)

## Suggested implementation PR sequence

- PR1: `bd-o9hv.1 + bd-o9hv.2`
- PR2: `bd-o9hv.3 + bd-o9hv.7`
- PR3: `bd-o9hv.4 + bd-o9hv.5 + bd-o9hv.6`

This keeps risk low while preserving dependency order and review clarity.

## Operator handoff checklist

- [ ] Confirm Beads epic and dependencies: `bd show bd-o9hv && bd children bd-o9hv`
- [ ] Confirm runtime baseline from a live job on one Linux VM and one macOS host
- [ ] Land PR sequence with Feature-Key trailers (`Feature-Key: bd-o9hv`)
- [ ] Post evidence paths in Beads notes for each subtask
- [ ] Close `bd-o9hv` only after all child tasks are closed and documented
