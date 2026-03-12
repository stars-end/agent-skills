# OpenCode Server Surface Audit

Date: 2026-03-12
Scope: remaining `localhost:4105` / `opencode serve` dependencies in `agent-skills`

## Verdict

Default DX execution is now CLI-first:

- `dx-runner --provider opencode` should use headless `opencode run`
- shared `opencode serve` services on canonical hosts are not required for standard `dx-runner` or `dx-loop` operation

There are still legacy server-mode surfaces in the repo. They should be treated as retired or opt-in only.

## Required

None for the default governed OpenCode lane.

The current required path is:

- headless CLI dispatch via `dx-runner`
- direct `opencode run`

## Legacy / Retired

### Retired runtime services

- `systemd/opencode.service`
  - legacy background OpenCode HTTP server using `op run --env-file ...`
  - caused fleet-wide restart storms and 1Password quota burn
- `systemd/opencode-server.service`
  - legacy agent-coordination server surface on port `4105`
  - retired on `homedesktop-wsl`

### Legacy diagnostics / operator checks

- `scripts/dx-doctor.sh`
  - previously treated `opencode.service` and `localhost:4105` health as expected
  - should now warn only if legacy server mode is still active

### Legacy coordination scripts

- `extended/slack-coordination/slack-coordinator.py`
  - assumes OpenCode HTTP server availability
  - now quarantined behind explicit opt-in
- `extended/slack-coordination/opencode-cleanup.sh`
  - assumes `localhost:4105/session`
  - now quarantined behind explicit opt-in

### Legacy documentation / examples

- `docs/DX_RUNNER_RUNBOOK.md`
- `extended/opencode-dispatch/SKILL.md`
- `scripts/publish-baseline.zsh`
- `AGENTS.md`
- `dist/universal-baseline.md`
- `dist/dx-global-constraints.md`

These references should be read as historical or advanced opt-in examples, not as the default fleet contract.

### Legacy benchmark / research surfaces

- `scripts/benchmarks/opencode_cc_glm/*`
- `scripts/test_p6_integration.py`
- `scripts/test_integration.py`
- `scripts/poc_session_status.py`
- `scripts/verify-coordinator.py`
- `scripts/ralph/*`
- `docs/bd-agent-skills-4l0/*`
- `docs/AUTONOMOUS_SLACK_DISPATCH.md`
- `docs/MULTI_AGENT_COMMS.md`
- `docs/opencode-investigation-prompt.md`

These remain useful as historical research or explicit server-mode experiments, but they do not define the current default runtime.

## Runtime findings that drove retirement

### Quota-burning loopers

- `epyc6` `opencode.service`
  - `NRestarts=98521`
  - failed with `Too many requests`
  - `.config/opencode/.env` contained 8 `op://` refs
- `homedesktop-wsl` `opencode.service`
  - `NRestarts=21304`
  - failed with `Too many requests`
- `epyc12` `opencode.service`
  - `NRestarts=16537`
  - failed with `243/CREDENTIALS`
- `epyc12` `slack-coordinator.service`
  - `NRestarts=16537`
  - failed with `243/CREDENTIALS`
- `homedesktop-wsl` `slack-coordinator.service`
  - `NRestarts=4657`
  - failed with `200/CHDIR`

## Current policy

1. Do not require `localhost:4105` for standard runner health.
2. Do not auto-install or auto-enable OpenCode server units in hydration/bootstrap flows.
3. If server mode is needed for a benchmark or legacy integration, require explicit operator opt-in.
