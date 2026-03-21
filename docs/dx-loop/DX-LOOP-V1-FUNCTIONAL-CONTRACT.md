# dx-loop v1 Functional Contract

**Status:** FROZEN  
**Version:** 1.0.0  
**Date:** 2026-03-20  
**Epic:** bd-5w5o  

---

## Purpose

This document defines the frozen functional contract for dx-loop v1. All implementations, integrations, and extensions must conform to this specification. Changes to this contract require a new version (v2).

---

## 1. v1 Scope (Canonical Surface)

### 1.1 Supported Commands

| Command | Description | Status |
|---------|-------------|--------|
| `dx-loop start --epic <id>` | Start wave from Beads epic | REQUIRED |
| `dx-loop status [--wave-id <id>]` | Show wave status | REQUIRED |
| `dx-loop status --json` | JSON output for automation | REQUIRED |

### 1.2 Supported Providers

| Provider | Role | Status |
|----------|------|--------|
| `opencode` | Primary implementation lane | REQUIRED |
| `cc-glm` | Reliability backstop via dx-runner | OPTIONAL |

### 1.3 Supported Modes

| Mode | Description | Status |
|------|-------------|--------|
| Implement | Execute Beads task with `tech-lead-handoff` return | REQUIRED |
| Review | Consume `implementation_return`, enforce `dx-loop-review-contract` | REQUIRED |

---

## 2. Non-Goals (Explicitly Out of Scope for v1)

| Non-Goal | Reason | Defer To |
|----------|--------|----------|
| Auto-merge | Human merge approval preserved per AGENTS.md | v2+ |
| Multi-epic parallelism | Single-epic wave focus | v2 |
| Custom provider plugins | Only opencode/cc-glm supported | v2 |
| Web UI | CLI-only for v1 | v2+ |
| Real-time streaming | Polling-based status | v2 |
| Cross-VM dispatch | Single-host orchestration | v2 |
| Automatic Beads closure | Orchestrator owns completion but human confirms | Future |

---

## 3. dx-runner Substrate Contract

### 3.1 Execution Model

All task execution flows through `dx-runner`:

```
dx-loop → dx-runner start --provider opencode --beads <id> --prompt-file <path>
         → dx-runner check --beads <id> --json
         → dx-runner report --beads <id> --format json
```

### 3.2 Required dx-runner Capabilities

| Capability | Contract |
|------------|----------|
| `start --provider opencode` | Must accept prompt-file argument |
| `check --json` | Must return `{status, pid, log_path, reason_code, next_action}` |
| `report --format json` | Must return `{outcome, metrics, artifacts}` |

### 3.3 Governance Gates

dx-runner gates that dx-loop respects:

| Gate | Behavior |
|------|----------|
| Preflight | Blocks dispatch if failed |
| Permission | Blocks dispatch if denied |
| Baseline/Integrity | Affects classification, may block |

---

## 4. OpenCode Implement/Review Lanes

### 4.1 Implementation Lane

**Provider:** `opencode`  
**Model:** `zhipuai-coding-plan/glm-5` (canonical)

**Prompt Structure:**
```
Follows $prompt-writing contract:
- MODE: initial_implementation
- BEADS_EPIC, BEADS_SUBTASK, BEADS_DEPENDENCIES
- FEATURE_KEY
- TARGET_REPO
- Objective from Beads task
- Required Execution Plan
- Required Deliverables
- Done Gate
```

**Return Structure:**
```
Follows $tech-lead-handoff MODE: implementation_return:
- PR_URL: concrete URL
- PR_HEAD_SHA: 40-char hex
- Validation: PASS|FAIL per command
- Changed Files Summary
- Risks / Blockers
- Decisions Needed
- How To Review
```

### 4.2 Review Lane

**Provider:** `opencode` (same model)

**Input:** Consumes `implementation_return` from implementation lane

**Contract:** Enforces `dx-loop-review-contract`:
- Findings first
- Concrete verdicts: `APPROVED`, `REVISION_REQUIRED`, `BLOCKED`
- No "looks good" without evidence

**Return Structure:**
```
VERDICT: APPROVED | REVISION_REQUIRED | BLOCKED
FINDINGS:
- <finding 1>
- <finding 2>
NEXT_ACTION: <actionable step>
```

---

## 5. Human Merge Only Policy

### 5.1 Policy

**NO AUTO-MERGE.** dx-loop v1 never automatically merges PRs.

### 5.2 Merge-Ready Detection

dx-loop classifies a task as `merge_ready` when:

1. `PR_URL` is present and valid
2. `PR_HEAD_SHA` matches current branch HEAD
3. CI checks passing (via GitHub API)
4. No `REVISION_REQUIRED` or `BLOCKED` verdicts

### 5.3 Human Action Required

When `merge_ready`:
- dx-loop emits notification (if configured)
- Operator must merge via GitHub web UI
- Follow `merge-pr` skill guidance

---

## 6. PR Artifact Requirement

### 6.1 Required Fields

| Field | Format | Validation |
|-------|--------|------------|
| `PR_URL` | `https://github.com/<org>/<repo>/pull/<n>` | URL regex |
| `PR_HEAD_SHA` | 40-char hex string | SHA regex |

### 6.2 Extraction

PR artifacts are extracted from implementer output:
- Parse `PR_URL: <url>` line
- Parse `PR_HEAD_SHA: <sha>` line
- Both required for completion

### 6.3 Missing Artifacts

Missing PR artifacts means **incomplete**, not success:
- Wave continues
- No merge-ready classification
- Implementer may be redispatched

---

## 7. Blocker Taxonomy

### 7.1 Blocker Codes

| Code | Severity | Meaning | Next Action |
|------|----------|---------|-------------|
| `kickoff_env_blocked` | error | Bootstrap/worktree/host gates failed | Fix bootstrap environment |
| `run_blocked` | error | dx-runner execution blocked | Wait or switch provider |
| `review_blocked` | error | Reviewer verdict blocked | Address review findings |
| `waiting_on_dependency` | warning | No ready tasks, upstream deps unmet | Wait for upstream |
| `deterministic_redispatch_needed` | warning | Stalled/timeout, safe to retry | Automatic redispatch |
| `needs_decision` | critical | Requires human decision | Human intervention |
| `merge_ready` | info | PR artifacts present, checks passing | Human merge approval |

### 7.2 Classification Rules

Blockers are classified via `configs/dx-loop/blocker_taxonomy.yaml`:

```yaml
runner_reason_map:
  worktree_missing: kickoff_env_blocked
  preflight_failed: kickoff_env_blocked
  provider_concurrency_cap_exceeded: run_blocked
  stalled_no_progress: deterministic_redispatch_needed
  max_attempts_exceeded: needs_decision
```

### 7.3 Unchanged Suppression

Identical blocker states are suppressed:
- Hash-based detection (SHA256)
- Only log every N occurrences (configurable)
- Reduces operator noise

---

## 8. Wave Advancement Behavior

### 8.1 Topological Dependency

Tasks are executed in dependency order:
1. Load epic from Beads
2. Build dependency graph
3. Compute frontier (tasks with all deps met)
4. Dispatch frontier tasks in parallel (up to `max_parallel`)
5. On completion, recompute frontier
6. Repeat until no tasks remain

### 8.2 Zero-Dispatch Handling

When frontier has zero dispatchable tasks:

| State | Code | Behavior |
|-------|------|----------|
| Dependency blocked | `waiting_on_dependency` | Persist state, exit |
| All complete | N/A | Wave complete |
| Initial frontier empty | `waiting_on_dependency` | Persist state, exit |

### 8.3 Retry Bounds

| Parameter | Default | Description |
|-----------|---------|-------------|
| `max_attempts` | 3 | Max dispatch attempts per task |
| `max_revisions` | 3 | Max revision cycles |
| `max_parallel` | 2 | Max concurrent tasks |

### 8.4 Wave State Persistence

State persisted to `/tmp/dx-loop/waves/<wave-id>/loop_state.json`:

```json
{
  "wave_id": "wave-2026-03-20T12-00-00Z",
  "epic_id": "bd-5w5o",
  "state": "running|blocked|complete",
  "tasks": {
    "bd-5w5o.1": {
      "status": "dispatched|reviewing|complete|blocked",
      "attempts": 1,
      "pr_url": null,
      "pr_head_sha": null,
      "blocker_code": null
    }
  },
  "blocked_details": {
    "blocked_tasks": ["bd-5w5o.2"],
    "unmet_dependencies": ["bd-5w5o.1"]
  }
}
```

---

## 9. Configuration Contract

### 9.1 Default Configuration

Location: `configs/dx-loop/default_config.yaml`

```yaml
max_attempts: 3
max_revisions: 3
max_parallel: 2
cadence_seconds: 600
provider: opencode
require_review: true
```

### 9.2 Environment Overrides

Configuration can be overridden via:
- `--config <path>` flag
- Environment variables (prefix `DX_LOOP_`)

---

## 10. Notification Contract

### 10.1 Notification Events

| Event | Notify | Suppress |
|-------|--------|----------|
| `merge_ready` | Yes | No |
| `needs_decision` | Yes | No |
| `kickoff_env_blocked` | Yes | No |
| `review_blocked` | Yes | No |
| `deterministic_redispatch_needed` | No | Yes |
| Unchanged blocker state | No | Yes |

### 10.2 Notification Channels

| Channel | Configuration | Status |
|---------|---------------|--------|
| Slack webhook | `notifications.slack_webhook_url` | OPTIONAL |
| Log file | `/tmp/dx-loop/waves/<wave-id>/logs/` | REQUIRED |

---

## 11. Artifact Locations

```
/tmp/dx-loop/
├── waves/<wave-id>/
│   ├── loop_state.json      # Persistent wave state
│   ├── logs/                 # Wave execution logs
│   └── outcomes/             # Task outcome artifacts
└── prompts/                  # Generated prompt files
```

---

## 12. Conformance Checklist

Implementations claiming dx-loop v1 conformance must:

- [ ] Support `start`, `status` commands
- [ ] Route all execution through dx-runner
- [ ] Enforce PR artifact contract (PR_URL + PR_HEAD_SHA)
- [ ] Implement 7-blocker taxonomy classification
- [ ] Never auto-merge PRs
- [ ] Support opencode provider with canonical model
- [ ] Persist wave state to `/tmp/dx-loop/waves/`
- [ ] Respect `max_attempts`, `max_revisions`, `max_parallel` bounds
- [ ] Emit `tech-lead-handoff` compatible implementation returns
- [ ] Consume `dx-loop-review-contract` for review lane

---

## References

- ADR: `docs/adr/ADR-DX-LOOP-V1.md`
- Skill: `extended/dx-loop/SKILL.md`
- Config: `configs/dx-loop/default_config.yaml`
- Blocker Taxonomy: `configs/dx-loop/blocker_taxonomy.yaml`
- Review Contract: `extended/dx-loop-review-contract/SKILL.md`
- dx-runner: `extended/dx-runner/SKILL.md`
- prompt-writing: `extended/prompt-writing/SKILL.md`
- tech-lead-handoff: `core/tech-lead-handoff/SKILL.md`
