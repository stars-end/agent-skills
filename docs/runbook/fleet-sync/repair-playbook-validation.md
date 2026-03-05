# Fleet Sync Repair Playbook Validation

## Scope
Validation for bd-d8f4.4: prove failure signatures and deterministic recovery commands for red states.

## Forced Failure Cases

### 1) Auth-readiness failure
```bash
OP_SERVICE_ACCOUNT_TOKEN= \
DX_SLACK_WEBHOOK= \
DX_ALERTS_WEBHOOK= \
./scripts/dx-fleet-check.sh --json
```

Evidence:
- `/tmp/fleet-os-completion/check-red.json`
- `/tmp/fleet-os-completion/check-red.rc`
- `fleet_status` was `red`; `op_auth_readiness` and `alerts_transport_readiness` failed in local host checks.

### 2) Host-unreachable snapshot failure
From standard fleet check execution against canonical host set where snapshots are not currently readable:
- `/tmp/fleet-os-completion/check-red.json`
- `/tmp/fleet-os-completion/check-green.json` (same command with Slack token set; still remote snapshot failures)

Evidence behavior:
- Remote hosts `epyc6`, `epyc12`, `homedesktop-wsl` emitted `Unable to read Fleet Sync snapshot`.
- Host rows marked `red` and `hosts_failed` remained non-zero.

### 3) Tool repair signal and next action path
```bash
./scripts/dx-fleet-install.sh --json
./scripts/dx-fleet-repair.sh --json --state-dir /tmp/fleet-pass-fixture
./scripts/dx-fleet-repair --json --state-dir /tmp/fleet-fail-fixture
```

Evidence:
- `/tmp/fleet-os-completion/repair-pass.json` (`overall_ok=true`, `fleet_status=green`, `repair_hints=[]`)
- `/tmp/fleet-os-completion/repair-fail.json` (`overall_ok=false`, `fleet_status=red`, `reason_codes=["repair_complete"]`, `repair_hints` populated)
- `repair-fail` exits with non-zero and includes machine-readable `reason_codes`, `reason_code`, `next_action`.

## Representative Recovery Loop
Observed local deterministic loop:
1. Detect red (`check` JSON + reason rows).
2. Run `dx-fleet repair --json` on impacted state fixture.
3. Re-run check once remediation is completed.

For the current canonical environment, the loop is partially simulated with state fixtures because remote hosts are not currently readable in this session. The required artifact contract and command output shape were still satisfied.

## Remediation Runbook (Operator)
- Red from local auth transport: set `OP_SERVICE_ACCOUNT_TOKEN` and `DX_SLACK_WEBHOOK`/`DX_ALERTS_WEBHOOK`.
- Red from snapshot reachability: fix SSH/connectivity and ensure `~/.dx-state/fleet/tool-health.json` exists on each host.
- Persistent red: run `./scripts/dx-fleet-check.sh --json --state-dir ...` then `./scripts/dx-fleet-repair.sh --json --state-dir ...`.

## Deterministic Commands
- Daily remediation: `./scripts/dx-fleet.sh repair --json --state-dir ~/.dx-state/fleet`
- Weekly + fleet health evidence refresh: `./scripts/dx-fleet.sh check --json --state-dir ~/.dx-state/fleet`

## Evidence paths
- `/tmp/fleet-os-completion/check-red.json`
- `/tmp/fleet-os-completion/check-green.json`
- `/tmp/fleet-os-completion/repair-pass.json`
- `/tmp/fleet-os-completion/repair-fail.json`
- `/tmp/fleet-os-completion/repair-pass.rc`
- `/tmp/fleet-os-completion/repair-fail.rc`
