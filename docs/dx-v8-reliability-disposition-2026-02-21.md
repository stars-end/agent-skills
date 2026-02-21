# DX V8 Reliability Disposition Matrix (2026-02-21)

Scope reviewed against merged baseline PR #218 (`d458fc8`) and current master lineage through PR #227 (`e519914`).

## Evidence Sources

- Full deterministic suite: `./scripts/test-dx-runner.sh` (131 pass / 0 fail in this branch)
- Smoke artifacts:
  - `/tmp/dx-smoke-bd-q3t9-20260221054553/preflight-real.log`
  - `/tmp/dx-smoke-bd-q3t9-20260221054553/provider-smoke-opencode.log`
  - `/tmp/dx-smoke-bd-q3t9-20260221054553/provider-smoke.log`
  - `/tmp/dx-smoke-bd-q3t9-20260221054553/provider-switch-smoke.log`
  - `/tmp/dx-smoke-bd-q3t9-20260221054553/explicit-repros.log`

## Matrix

| Issue | Repro on current master | Fixed by PR #218 | Disposition now | Evidence |
|---|---|---:|---|---|
| `bd-cbsb.19.3` | Yes (attach/server contract ambiguity) | No | Fixed in this PR: deterministic attach-mode fail-fast with `opencode_attach_mode_unavailable` / `opencode_attach_missing_url` | `test_opencode_attach_mode_failfast` + adapter preflight/start checks |
| `bd-cbsb.19.6` | Yes (cwd/worktree drift risk) | Partial | Fixed in this PR: OpenCode `start` pins resolved worktree and adapter enforces `--dir` existing path | `start_cmd` + `adapter_start` changes |
| `bd-cbsb.19.7` | Yes (missing Railway gate possible false-success setup) | No | Fixed in this PR: capability-aware Railway preflight gate (opt-in strict) | `test_railway_auth_preflight_requirement` |
| `bd-cbsb.19.9` | Yes (success without commit artifact possible) | No | Fixed in this PR: `--require-commit-artifact`/`DX_RUNNER_REQUIRE_COMMIT_ARTIFACT` contract with `no_commit_artifact` | `test_commit_required_contract` |
| `bd-cbsb.20` | Yes (strict model policy confusion across hosts) | Partial | Fixed in this PR: host/cwd/policy context in preflight and strict canonical enforcement retained | `preflight-real.log`, runbook/ADR updates |
| `bd-cbsb.21` | Yes (repo-id mismatch observed) | No | Not code-bug in runner core; remediation path already surfaced via beads-gate `next_action` (`run_bd_migrate_update_repo_id`) | `dx-runner beads-gate --json` reason mapping (existing + retained) |
| `bd-cbsb.23` | Yes (check/report metric loss after finalize) | Partial | Fixed in this PR: check/report consume finalized metrics (`mutation_count`, `log_bytes`, `cpu_time_sec`, `pid_age_sec`) | `test_check_metrics_telemetry`, `test_stop_preserves_metrics` |
| `bd-cbsb.24` | No (already fixed) | No | Fixed previously (PR #227 lineage) and retained; not regressed | `test_feature_key_validation`, commit hook behavior |
| `bd-q3t9` | Intermittent historically | Partial | Fixed in this PR with explicit no-orphan monitor cleanup validation | `test_completion_monitor_cleanup` |
| `bd-5wys.10` | No (already fixed) | No | Fixed previously; retained | `test_feature_key_validation` |
| `bd-5wys.12` | No (already fixed) | No | Fixed previously; retained | `test_precommit_flush_semantics` |
| `bd-5wys.13` | Partial | Partial | Fixed in this PR for check/report finalized telemetry | `test_check_metrics_telemetry`, provider-switch/report smokes |
| `bd-5wys.17` | Yes (host config mismatch) | No | Operational env issue; runner now emits deterministic remediation guidance, no additional core code needed | beads-gate reason/next_action output |
| `bd-5wys.20` | Yes | Partial | Fixed in this PR: strict canonical policy + host-context clarity + runbook alignment | preflight outputs + docs |
| `bd-cbsb.19.8` | Partial | Partial | Covered by existing/retained auto-trust + clearer preflight warnings; no extra code required | opencode preflight warning + start auto-trust |
| `bd-cbsb.19.5` | Partial | Partial | Same as above (mise trust drift) | opencode preflight and start trust behavior |
| `bd-cbsb.19.4` | Yes historically | Partial | Fixed via resolved worktree + `--dir` enforcement for OpenCode | start/adapter changes |
| `bd-cbsb.19.1` | Partial | Partial | Contract normalized further with deterministic attach mode handling and explicit reason taxonomy | attach-mode tests + runbook |
| `bd-cbsb.19.2` | Partial | Partial | Model/agent selection now fail-fast (no silent fallback) for OpenCode canonical model | `test_model_resolution` |
| `bd-5wys.18` | Partial | Partial | Existing auto-trust retained; no regression; documented | preflight warning + runbook |
| `bd-5wys.21` | No (already fixed) | Yes | Already fixed by baseline/lineage and retained | `test_provider_concurrency_guardrail` |
| `bd-5wys.22` | Partial | Partial | Existing diagnostics retained; no regression | worktree smoke + script diagnostics |
| `bd-5wys.16` | No (already fixed) | Yes | Already fixed by baseline/lineage and retained | `test_provider_switch_resolution` + `provider-switch-smoke.log` |

## New/Updated Reason Codes Added in This PR

- `no_commit_artifact`
- `opencode_attach_mode_unavailable`
- `opencode_attach_missing_url`
- `worktree_missing_for_opencode`
- railway gate diagnostics:
  - `railway_cli_missing`
  - `railway_auth_missing`
  - `railway_service_context_missing`

## Operator Notes

- Railway gate is now opt-in strict mode: `--require-railway-auth` or `DX_RUNNER_REQUIRE_RAILWAY_AUTH=1`.
- Commit artifact enforcement is opt-in: `--require-commit-artifact` or `DX_RUNNER_REQUIRE_COMMIT_ARTIFACT=1`.
