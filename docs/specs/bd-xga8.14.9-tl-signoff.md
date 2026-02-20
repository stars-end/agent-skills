# TL Signoff Gate — bd-xga8.14.9

Date: 2026-02-20
Reviewer: Tech Lead (orchestrator)
Decision: NO-GO (conditional)

## Findings (ordered by severity)

### [P1] 6-stream multi-provider soak gate fails in live run
- Evidence:
  - Command: `python3 scripts/validation/multi_provider_soak.py --rounds 2 --parallel 6 --timeout-sec 300 --output-dir artifacts/multi-provider-soak`
  - Run ID: `soak-20260220T015311Z`
  - Result: 4/12 passed, both rounds failed
  - Artifacts:
    - `artifacts/multi-provider-soak/soak-20260220T015311Z.json`
    - `artifacts/multi-provider-soak/soak-20260220T015311Z.md`
- Impact:
  - Epic acceptance "two consecutive clean rounds" is not yet met.

### [P1] cc-glm lane blocked by auth source on epyc12
- Evidence:
  - Command: `./scripts/dx-runner preflight --provider cc-glm`
  - Output: `NO_AUTH_SOURCE` and `No auth source configured and default op:// resolution failed`
  - Environment check: `op whoami` exit code `1` on epyc12.
- Impact:
  - cc-glm provider cannot participate in live multi-provider validation.

### [P1] Gemini lane fails at runtime with account verification challenge
- Evidence:
  - Gemini jobs in soak run exited `exited_err` with reason `process_exit_with_rc`.
  - Provider logs show `ValidationRequiredError: Verify your account to continue` (HTTP 403).
  - Sample logs:
    - `/tmp/dx-runner/gemini/soak-20260220T015311Z-r1-gemini-0.log`
    - `/tmp/dx-runner/gemini/soak-20260220T015311Z-r1-gemini-1.log`
- Impact:
  - Gemini provider cannot currently pass real throughput validation despite preflight success.

### [P2] dx-runner final report metrics can drift from in-run status
- Evidence:
  - During `bd-xga8.14.8` runtime, status showed nonzero mutations/log bytes.
  - Final `dx-runner report --beads bd-xga8.14.8 --format markdown` reported `Mutations: 0` and `Log Size: 0 bytes`.
- Impact:
  - Post-run reporting can understate real job activity and confuse operator decisions.

## What Passed
- OpenCode canonical model policy is enforced (`zhipuai-coding-plan/glm-5`).
- Unified runner, adapter structure, compat shims, and cutover docs are merged.
- Soak runner and unit tests exist and pass locally (`21 passed`).

## Required Unblocks Before GO
1. Restore cc-glm auth on epyc12 (`op`/token source available to preflight and start).
2. Re-verify Gemini account in headless lane so runtime calls do not hit verification 403.
3. Re-run live two-round soak and attach passing JSON/Markdown artifacts.
4. Fix/report drift for mutation/log metrics in final report outputs.

## Signoff Status
- This gate execution is complete.
- Final epic signoff is deferred until the 4 unblocks above are resolved and validated.
