# Fleet Sync Repair Playbook Validation

## Scope
Validation for bd-d8f4.4: required forced-failure recovery proof and documented remediation path.

## Forced Failure and Recovery Cases (Local Proof Harness)

### 1) Auth + transport readiness failure
```bash
unset OP_SERVICE_ACCOUNT_TOKEN DX_ALERTS_WEBHOOK DX_SLACK_WEBHOOK SLACK_BOT_TOKEN SLACK_APP_TOKEN SLACK_MCP_XOXP_TOKEN SLACK_MCP_XOXB_TOKEN
./scripts/dx-fleet.sh check --json --state-dir /tmp/fleet-platform-closeout-2026-03-05/repair-proof
./scripts/dx-fleet-repair.sh --json --state-dir /tmp/fleet-platform-closeout-2026-03-05/repair-proof
```

Artifacts:
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-transport-check.json`
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-repair.json`

### 2) Host snapshot/readability failure
```bash
printf '{bad json' > /tmp/fleet-platform-closeout-2026-03-05/repair-proof/tool-health.json
./scripts/dx-fleet.sh check --json --state-dir /tmp/fleet-platform-closeout-2026-03-05/repair-proof
```

Expected: check emits parse/fallback path and returns non-zero; remediation is to restore readable snapshot (`cp` from latest known good) and rerun install/check.

### 3) Tool drift remediation signal
```bash
mv ~/.gemini/GEMINI.md ~/.gemini/GEMINI.md.disabled
./scripts/dx-fleet.sh check --json
./scripts/dx-fleet-install.sh --check --state-dir /tmp/fleet-platform-closeout-2026-03-05/repair-proof
./scripts/dx-fleet-repair.sh --json --state-dir /tmp/fleet-platform-closeout-2026-03-05/repair-proof
```

Expected: drift is surfaced as `fail`/`warn` row(s), repair emits explicit next actions, and follow-up operator restore returns to steady-state check.

## Evidence of Recovery Loop
Representative local recovery flow used in this run:
1. Create/observe failing local check (`fail-auth-transport-check.json`).
2. Run repair and capture machine-readable hints (`fail-auth-repair.json`, `next_action="rerun"`).
3. Restore required environment (`OP_SERVICE_ACCOUNT_TOKEN` and transport token/webhook), then rerun check for green post-remediation.

## Required Artifacts
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-transport-check.json`
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-transport-check.rc`
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-repair.json`
- `/tmp/fleet-platform-closeout-2026-03-05/repair-proof-artifacts/fail-auth-repair.rc`
