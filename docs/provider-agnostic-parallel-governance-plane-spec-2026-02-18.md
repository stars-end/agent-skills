# Provider-Agnostic Parallel Governance Plane Spec (DX v8.x)

Date: 2026-02-18
Epic: `bd-cbsb`
Scope: `agent-skills` only

## 1. Objective

Build one governance/control plane that is provider-agnostic and adapter-driven, so OpenCode, cc-glm, Gemini, and future models can be swapped without changing orchestration safety logic.

This spec explicitly preserves the existing DX v8.x reliability learnings while sequencing rollout as:
1. OpenCode harness completion + real coding test.
2. Shared governance extraction.
3. Deferred DX v8.x residual fixes integration (including cc-glm hardening deltas).

## 2. Problem Statement

Current execution has two gaps:
1. Governance logic is partially coupled to provider-specific paths (`cc-glm-job.sh` behaviors and OpenCode harness behaviors are not unified).
2. Critical reliability controls are inconsistent across lanes (startup ambiguity, baseline drift, report integrity, mutation visibility).

Consequence: model comparison is valid, but production orchestration behavior is not fully deterministic across providers under 6-9 parallel streams.

## 3. Evidence Baseline

Benchmark evidence (2026-02-18):
- Artifact: `artifacts/opencode-cc-glm-bench/real-r1-r2-r3-cc-op-gemini-combined-20260218T0533Z.json`
- OpenCode: 100% success, best latency medians.
- cc-glm: 100% success, slower latency, higher output consistency on rubric hints.
- Gemini: lower reliability due to quota/rate-limit variability.

Residual operational evidence:
- `/Users/fengning/prime-radiant-ai-v2/docs/cc-glm-dx-v8-residual-issues-brief-2026-02-18.md`
- `/Users/fengning/prime-radiant-ai-v2/docs/cc-glm-headless-issues-log-2026-02-17.md`
- Active blocked wave context: `bd-xga8.2.2`

## 4. Requirements

### 4.1 P0 Requirements (Mandatory)

1. Startup/no-output ambiguity elimination:
- Deterministic substate classification for `launching`, `waiting_first_output`, `stalled`, `silent_mutation`.
- No terminal `running` state without actionable `reason_code`.

2. Pre-dispatch runtime baseline gate:
- Fail fast when runtime baseline on target host/repo is below required commit/tag.

3. Post-wave report integrity gate:
- Verify reported commit exists.
- Verify reported commit is ancestor of branch head.

4. Mutation-first visibility:
- Status/check must surface worktree mutation signals even when logs are empty.

### 4.2 P1 Requirements

5. Monitor-loop ergonomics:
- Stable machine-readable status fields for automation.

6. Feature-Key governance:
- Validate task-specific Feature-Key trailers before PR creation.

## 5. Architecture

## 5.1 Core Components

1. Governance Runner (shared):
- Dispatch lifecycle engine.
- Retry/backoff policy.
- Gate enforcement.
- Unified telemetry.

2. Provider Adapters (pluggable):
- OpenCode adapter.
- cc-glm adapter.
- Gemini adapter.

3. Evidence Pipeline:
- Raw logs and structured records.
- Collector.
- Summarizer.

4. Gate Engine:
- Baseline gate.
- Runtime-state gate.
- Integrity gate.
- Feature-Key gate.

## 5.2 Adapter Interface Contract

Each adapter must implement:

1. `prepare(job_spec) -> adapter_context`
2. `start(adapter_context) -> attempt_handle`
3. `poll(attempt_handle) -> status_event`
4. `stop(attempt_handle) -> stop_result`
5. `collect(attempt_handle) -> attempt_result`
6. `classify(raw_error) -> {failure_category, failure_reason}`

Common `attempt_result` fields:
- `success` (bool)
- `return_code` (int|null)
- `timed_out` (bool)
- `startup_latency_ms` (int|null)
- `first_output_latency_ms` (int|null)
- `completion_latency_ms` (int|null)
- `stdout` (sanitized string)
- `stderr` (sanitized string)
- `failure_category` (`harness|model|env|null`)
- `failure_reason` (string|null)
- `hint_match_ratio` (0.0-1.0)
- `session_id` (string|null)
- `used_model_fallback` (bool)

## 5.3 Unified State Machine

`created -> preflight -> launching -> waiting_first_output -> running_with_output -> completed_success|completed_failure`

Exceptional substates:
- `baseline_failed`
- `silent_mutation`
- `stalled`
- `blocked` (retry budget exhausted)

Each state transition emits:
- `state`
- `substate`
- `reason_code`
- `observed_at`
- `evidence_ref`

## 6. Governance Gates

## 6.1 Pre-dispatch Baseline Gate

Input:
- `required_baseline` (commit SHA or release marker)
- `runtime_commit` (host/repo commit)

Rule:
- Pass only if `runtime_commit` is at/after required baseline via merge-base ancestry check.

Failure:
- Mark as `baseline_failed`.
- Do not dispatch jobs.

## 6.2 Startup Ambiguity Gate

Rule:
- If process is running with no output, classify as:
  - `waiting_first_output` if within startup grace and progress/mutation evidence exists.
  - `stalled` if grace exceeded and no progress evidence.
  - `silent_mutation` if worktree changes exist while output remains empty.

## 6.3 Post-wave Commit Integrity Gate

For each reported commit:
1. `git cat-file -e <sha>^{commit}`
2. `git merge-base --is-ancestor <sha> <branch_head>`

Failure categories:
- `harness/integrity_missing_commit`
- `harness/integrity_not_ancestor`

## 6.4 Feature-Key Governance Gate

Before PR creation:
- Validate commit trailers include the task-specific `Feature-Key: bd-...`.
- Reject or block PR flow on mismatch.

## 7. Telemetry and Output Contract

Every run must include:
- `run_id`
- `workflow_id`
- `system`
- `model`
- `prompt_id`
- `job_started_at`
- `job_completed_at`
- `success`
- `retry_count`
- latency metrics
- `failure_category` / `failure_reason`
- `state_transitions` (or equivalent substate evidence)

Outputs:
1. Machine-readable JSON (`results.json`, `records.ndjson`, `summary.json`)
2. Markdown summary (`summary.md`)

Logs:
- Sanitized for secrets/token patterns.

## 8. Lane Routing Policy

Policy inputs:
- `criticality` (`critical|standard`)
- `provider_health`
- `recent_failure_rate`
- `quota_headroom`

Routing:
1. Default throughput: OpenCode (`zai-coding-plan/glm-5`)
2. Backstop/fallback: cc-glm (`glm-5`)
3. Optional overflow: Gemini (only with quota gate pass)

Important: routing decision is orchestrator policy, not agent ad hoc behavior.

## 9. Existing DX v8.x Fixes To Preserve

From prior hardening waves (`bd-xga8.10`, `bd-xga8.11`), preserve:
- Progress-aware health semantics.
- Startup classification improvements.
- Contract-oriented restart behavior.
- Mutation detection surfaces.
- Preflight and auth hardening patterns.

Residual fixes still required are captured in `bd-cbsb.10` and deferred by gate until OpenCode certification is complete.

## 10. Phased Rollout (Beads-Backed)

Epic: `bd-cbsb`

Phase A (OpenCode-first harness):
- `bd-cbsb.1` Spec
- `bd-cbsb.2` Shared runner
- `bd-cbsb.3` OpenCode adapter
- `bd-cbsb.4` OpenCode 6-stream launcher
- `bd-cbsb.5` Collector/summarizer
- `bd-cbsb.6` OpenCode real coding wave
- `bd-cbsb.7` OpenCode certification gate

Phase B (shared extraction):
- `bd-cbsb.8` Shared governance extraction
- `bd-cbsb.9` cc-glm adapter migration

Phase C (deferred DX fixes):
- `bd-cbsb.10` Residual DX v8.x fix integration (gated on `bd-cbsb.7` + `bd-cbsb.9`)
- Cross-link blocker: `bd-xga8.2.2` depends on `bd-cbsb.10`

Phase D (multi-provider completion):
- `bd-cbsb.11` Gemini adapter
- `bd-cbsb.12` 9-stream mixed soak
- `bd-cbsb.13` Runbook + rollout policy

## 11. Validation Matrix

Script validation:
- `bash -n extended/cc-glm/scripts/cc-glm-headless.sh`
- `bash -n extended/cc-glm/scripts/cc-glm-job.sh`

Deterministic tests:
- `bash extended/cc-glm/scripts/test-cc-glm-auth-resolver.sh`
- `bash extended/cc-glm/scripts/test-cc-glm-job-v33.sh`
- New governance/adapter tests (this epic)

Benchmark validations:
- OpenCode-only phase pass.
- OpenCode real coding test pass.
- Mixed-lane soak pass after deferred fix integration.

## 12. Success Criteria

1. Same prompt set runs reproducibly across adapters.
2. Side-by-side table auto-generated.
3. Failure taxonomy consistently populated (`harness|model|env`).
4. No ambiguous running/no-output states without explicit substate and reason.
5. Integrity gates block invalid reports before PR/merge flow.
