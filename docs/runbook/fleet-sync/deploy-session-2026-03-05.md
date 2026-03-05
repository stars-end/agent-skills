# Fleet Sync Deploy Session — 2026-03-05

## Gate Decision
- Patch-scope compatibility fixes (bash 3.2 + daily wrapper contract): **GO**
- Fleet rollout gate for bd-d8f4.2 closure: **NO-GO**

## Wave Objective
- Execute Fleet Sync install/check across canonical hosts for bd-d8f4.2 closure evidence.
- Record per-host command outcomes and collect best-effort evidence payloads.

## Commands Executed
```bash
for vm in macmini homedesktop-wsl epyc6 epyc12; do
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-install.sh --json"
  ssh "$vm" "~/agent-skills/scripts/dx-fleet-check.sh --json"
done
```

## Evidence
- Raw session capture: `/tmp/fleet-deploy-session/session-2026-03-05.md`
- Raw session log: `/tmp/fleet-deploy-session/session-2026-03-05.log`
- Historical host fixture captures:
  - `/tmp/fleet-deploy-session/*-install.json`
  - `/tmp/fleet-deploy-session/*-check.json`
  - `/tmp/fleet-deploy-session/*-install-v2.json`
  - `/tmp/fleet-deploy-session/*-check-v2.json`

## Results (Observed)
- `macmini install` failed with SSH auth failure: `Too many authentication failures`.
- `homedesktop-wsl`, `epyc6`, `epyc12 install` returned command-not-found (`dx-fleet-install.sh` missing at remote path `/home/fengning/agent-skills/scripts/dx-fleet-install.sh`).
- `check` runs on reachable hosts were executed but returned fleet checks with multiple unreachable hosts.

## Command-by-Command Status
- `macmini install`: **rc=255** (SSH auth)
- `homedesktop-wsl install`: **rc=127** (missing script path)
- `epyc6 install`: **rc=127** (missing script path)
- `epyc12 install`: **rc=127** (missing script path)
- `check` commands produced mixed local/remote checks and did not converge to green due SSH access and stale artifacts.

## Root Cause Notes
- Install script rollout is incomplete on several canonical hosts (`/home/fengning/agent-skills` path mismatch).
- Current SSH auth profile for `macmini` does not permit execution from this environment.

## State & follow-up
- Preserve collected artifacts above for GA handoff and next-wave deployment planning.
- Before re-running, ensure `/home/fengning/agent-skills/scripts/dx-fleet-install.sh` exists on all canonical hosts and SSH auth keys are valid.
- Do not claim epic completion until this deploy wave is rerun with converged host evidence.

## Landing Pass Re-Run (2026-03-05T20:35Z to 20:53Z)

### Remediations Applied
- Synced Fleet Sync scripts/manifests to `homedesktop-wsl`, `epyc6`, `epyc12`.
- Repaired cross-host SSH trust fabric:
  - distributed canonical host public keys to all hosts' `~/.ssh/authorized_keys`
  - refreshed `~/.ssh/known_hosts` for `macmini`, `homedesktop-wsl`, `epyc6`, `epyc12`
  - fixed `homedesktop-wsl` SSH config for `epyc6` user (`feng` -> `fengning`)
- Re-ran install/check/repair with service-account and Slack tokens injected for runtime readiness checks.
- Patched and redeployed host identity/state path logic:
  - `scripts/canonical-targets.sh` host detection now prefers Tailscale self DNS name.
  - `scripts/dx-fleet-check.sh` local host detection uses canonical host key fallback.
  - `scripts/dx-fleet-check.sh` remote snapshot lookup now probes `/home/<user>` and `/Users/<user>` state roots.

### Current Convergence Outcome
- `macmini`: red
- `homedesktop-wsl`: red
- `epyc6`: red
- `epyc12`: red

All hosts are now red for a narrowed reason:
- Remaining fail check: `tool_mcp_health` on `epyc6` and `epyc12` snapshots.
- Remote snapshot transport is now mostly healthy; failure scope reduced from broad transport/auth failures to MCP lane drift on Linux EPYC hosts.

### New Evidence (Landing Pass)
- `/tmp/fleet-land-plane-2026-03-05/preflight-ssh.txt`
- `/tmp/fleet-land-plane-2026-03-05/preflight-ssh-after-sync.txt`
- `/tmp/fleet-land-plane-2026-03-05/sync-linux-hosts.txt`
- `/tmp/fleet-land-plane-2026-03-05/ssh-mesh.txt`
- `/tmp/fleet-land-plane-2026-03-05/ssh-failures-retest.txt`
- `/tmp/fleet-land-plane-2026-03-05/rollout-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/rollout-summary-auth.txt`
- `/tmp/fleet-land-plane-2026-03-05/check-postpatch-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/check-final-summary.txt`
- `/tmp/fleet-land-plane-2026-03-05/check-greenrun-summary.txt`

### Gate Status
- bd-d8f4.2 rollout gate: **NO-GO**
- Blocker: fleet not yet green on all 4 hosts; `epyc6` and `epyc12` still fail `tool_mcp_health`.
