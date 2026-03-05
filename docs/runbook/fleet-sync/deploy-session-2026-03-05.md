# Fleet Sync Deploy Session — 2026-03-05

## Gate Decision
- Patch-scope compatibility fixes (bash 3.2 + daily wrapper contract): **GO**
- Fleet rollout gate for bd-d8f4.2 closure: **NO-GO**

## Scope
- Execute Fleet Sync install/check across canonical hosts for rollout evidence.
- All evidence is now captured under `/tmp/fleet-platform-closeout-2026-03-05/`.

## Commands Executed
```bash
for vm in macmini homedesktop-wsl epyc6 epyc12; do
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-install.sh --json"
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-check.sh --json"
  ssh "$vm" "~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet"
done
```

## Evidence
- Master evidence directory: `/tmp/fleet-platform-closeout-2026-03-05/`
- Per-host artifacts:
  - `/tmp/fleet-platform-closeout-2026-03-05/hosts/*-install.json`
  - `/tmp/fleet-platform-closeout-2026-03-05/hosts/*-check.json`
  - `/tmp/fleet-platform-closeout-2026-03-05/hosts/*-mcp-check.json`
- Aggregated summaries:
  - `/tmp/fleet-platform-closeout-2026-03-05/check-summary.txt`
  - `/tmp/fleet-platform-closeout-2026-03-05/check-summary.json`
  - `/tmp/fleet-platform-closeout-2026-03-05/hosts/host-collect-summary.csv`

## Results (Observed)
- `macmini`, `epyc6`, `epyc12` install/check runs are consistently returning checks and remain **red**.
- `homedesktop-wsl` currently misses canonical script paths at `/home/fengning/agent-skills/scripts/...` (install/mcp command path mismatch).
- Remaining known runtime failure classes are:
  - `op_auth_readiness` missing token across hosts with `op` present.
  - `alerts_transport_readiness` missing transport/webhook in this environment.

## Current Rollout Status
- `bd-d8f4.2` remains **NO-GO** until all 4 hosts are green under required checks in a fresh full-run.

## Next Command Set (exact)
```bash
ssh <vm> "~/agent-skills/scripts/dx-fleet-install.sh --json --state-dir ~/.dx-state/fleet"
ssh <vm> "~/agent-skills/scripts/dx-fleet-check.sh --json --state-dir ~/.dx-state/fleet"
ssh <vm> "~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json --state-dir ~/.dx-state/fleet"
```
