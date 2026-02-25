# DX Reliability Audit — bd-g2cw (2026-02-25)

## Scope
This audit covers hardening and drift cleanup across `dx-runner`, `dx-batch`, `dx-wave`, `dx-dispatch`, and DX V8.x docs/contracts in `/Users/fengning/agent-skills`.

In-scope Beads:
- `bd-g2cw` (`.1`, `.2`, `.3`, `.4`)
- `bd-9hq0` (`.1`–`.8`)
- `bd-cbsb.27`

## Root Causes
1. Runtime path drift on epyc12: `dx-batch` and `dx-wave` not installed into `~/bin`; `dx-dispatch` symlink pointed at deprecated Python implementation.
2. Wrapper gap: no deterministic fallback behavior when operators expect batch orchestration but `dx-batch` is unavailable.
3. Worktree inference ambiguity: `dx-runner start --provider opencode` launched from non-git home cwd could fail with ambiguous external-directory/worktree errors.
4. Telemetry drift risk: `stop` could overwrite richer finalized metrics with lower snapshots.
5. Preflight noise: `opencode` mise trust warnings could appear even when no `.mise.toml` target was relevant.
6. Contract drift: `dx-batch` lacked explicit `check/report` reason-code parity with `dx-runner`.
7. Docs drift: host capability docs still reported epyc12 lacking `op` CLI.

## Fixes Mapped to Beads
| Beads | Finding | Fix | Status |
|---|---|---|---|
| bd-g2cw.2 | Adopt saturation guard behavior into active path | Verified `dx-batch` cap/doctor gating + surfaced operator fallback in `dx-wave` | ✅ |
| bd-g2cw.4 | Failure taxonomy visibility | Added `dx-batch check/report`, wave/item `reason_code`, and schema updates | ✅ |
| bd-9hq0.2 | epyc12 missing `dx-batch` runtime tool | Updated `scripts/dx-ensure-bins.sh` to install `dx-batch`, `dx-wave`, and wrapper `dx-dispatch` | ✅ (code), rollout pending merge |
| bd-9hq0.6 | report/accounting drift | Preserved stronger prior metrics during manual stop before writing outcome | ✅ |
| bd-9hq0.8 | home-cwd worktree auto-reject edge | Hardened worktree resolution and explicit `reason_code=worktree_missing` | ✅ |
| bd-9hq0.4 | preflight `mise untrusted` noise | Scoped warning to concrete `.mise.toml` targets only | ✅ |
| bd-cbsb.27 | exec saturation runbook | Added runbook to `extended/dx-batch/SKILL.md` and `docs/DX_RUNNER_RUNBOOK.md` | ✅ |
| bd-9hq0.1 | docs/workflow capability mismatch | Updated skill/runbook docs + host capability docs | ✅ |
| bd-9hq0.3 | cross-host version/runtime drift | Added rollout validation + matrix evidence (see below) | ⚠️ Partial (auth limits on non-epyc12 hosts) |
| bd-g2cw.1 | stalled false positives/prune efficacy | Revalidated prune + health taxonomy in full runner test suite | ✅ |
| bd-g2cw.3 | epyc12 governance profile | Operationally covered via `dx-wave` profile-first lane and rollout checks | ✅ |
| bd-9hq0.5 / bd-9hq0.7 | dx-dispatch inventory drift | Kept compatibility shim, corrected `~/bin/dx-dispatch` target to wrapper in installer | ⚠️ Partial (legacy path still present until rollout) |

## Code Changes (High Impact)
- `scripts/dx-ensure-bins.sh`
  - Installs `dx-batch` and `dx-wave` to `~/bin`
  - Installs `dx-dispatch` wrapper (fallback to `.py` only if wrapper missing)
- `scripts/dx-wave`
  - Added `batch-start/batch-status/batch-resume/batch-cancel/batch-doctor`
  - Added deterministic fallback with `WARN_CODE=dx_batch_unavailable_fallback_runner`
- `scripts/dx-runner`
  - Hardened worktree resolution (`--worktree`/metadata/prompt ancestry/env/git cwd)
  - Explicit `reason_code=worktree_missing` on unresolved worktree
  - Preserves richer prior stop/report metrics to avoid telemetry regressions
- `scripts/adapters/opencode.sh`
  - Deterministic, scoped `mise trust` preflight noise policy
- `scripts/dx_batch.py`
  - Added wave/item `reason_code` state
  - Added `check` and `report` commands
  - Added reason-code derivation + next-action guidance parity
- `configs/dx-batch/schemas/wave_state.json`
  - Added `reason_code` for wave and item state
- Docs/skills updated:
  - `extended/dx-batch/SKILL.md`
  - `extended/dx-runner/SKILL.md`
  - `docs/DX_RUNNER_RUNBOOK.md`
  - `docs/CANONICAL_TARGETS.md`
  - `docs/CROSS_VM_VERIFICATION_MATRIX.md`

## Validation Evidence
### Local tests
- `pytest -q tests/dx_batch tests/test_dx_wave_fallback.py`
  - Result: **59 passed**
- `PATH=/opt/homebrew/bin:$PATH scripts/test-dx-runner.sh`
  - Result: **152 passed, 1 failed**
  - Known pre-existing flaky: `gemini success run did not finalize as exited_ok`

### epyc12 live dry-run
Mandatory gates executed from epyc12 are captured below.

#### Preflight and runtime checks
- Command(s):
  - `dx-runner preflight --provider opencode`
  - `dx-runner start/check/status/report` dry-run cycle
- Result: _Recorded after branch rollout to epyc12 worktree_

#### Saturation simulation
- Command(s):
  - `dx-batch start --items ... --exec-process-cap <small>`
  - `dx-batch doctor --wave-id <id> --json`
- Result: _Recorded after branch rollout to epyc12 worktree_

#### Stalled-job simulation
- Command(s):
  - synthetic stalled pid/log state + `dx-runner check`
  - `dx-runner prune --json`
- Result: _Recorded after branch rollout to epyc12 worktree_

## Host Capability Matrix (Current)
| Host | `dx-runner` on PATH | `dx-batch` on PATH | `dx-wave` on PATH | `op` CLI | Verification |
|---|---|---|---|---|---|
| epyc12 | ❌ (before rollout) | ❌ (before rollout) | ❌ (before rollout) | ✅ (`op 2.32.1`) | ✅ direct |
| macmini | unknown in this pass | unknown in this pass | unknown in this pass | unknown in this pass | ⚠️ SSH auth failure |
| homedesktop-wsl | unknown in this pass | unknown in this pass | unknown in this pass | unknown in this pass | ⚠️ SSH timeout/no response |

## Remaining Risks
1. Cross-host verification is incomplete for `macmini` and `homedesktop-wsl` due SSH/auth constraints in this run.
2. Legacy `dx-dispatch.py` still exists as break-glass path; full deprecation requires follow-up removal plan.
3. One pre-existing gemini finalization test remains flaky (`scripts/test-dx-runner.sh`).

## Follow-up
1. Complete post-merge host rollout (`dx-ensure-bins.sh`) on all canonical hosts and rerun capability matrix checks.
2. Close remaining drift issues after multi-host verification artifacts are attached.
