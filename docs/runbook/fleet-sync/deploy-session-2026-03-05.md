# Fleet Sync Deploy Session — 2026-03-05

## Gate Decision
- Patch-scope compatibility fixes (bash 3.2 + daily wrapper contract): **GO**
- Fleet rollout gate for bd-d8f4.2 closure: **GO**

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
- Host snapshot refresh run converged all 4 hosts to **green** for required runtime checks:
  - `macmini`: green
  - `homedesktop-wsl`: green
  - `epyc6`: green
  - `epyc12`: green
- epyc6 required one host-level token source fix: valid OP service-account token added at `~/.config/systemd/user/op-epyc6-token`.
- Remaining platform blocker is no longer rollout convergence; it is live Slack transport (`not_in_channel`) in cron posting.

## Current Rollout Status
- `bd-d8f4.2` is now eligible for closure based on green convergence evidence in the fresh run.

## Next Command Set (exact)
```bash
ssh <vm> "~/agent-skills/scripts/dx-fleet-check.sh --json --local-only --state-dir ~/.dx-state/fleet > ~/.dx-state/fleet/tool-health.json"
./scripts/dx-fleet-check.sh --json --state-dir ~/.dx-state/fleet
```
