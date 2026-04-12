---
name: bd-doctor
description: Diagnose and repair Beads reliability issues for the canonical `bdx` coordination path (`~/.beads-runtime/.beads` runtime, epyc12 host) across hosts.
tags: [health, beads, dolt, reliability, fleet]
allowed-tools:
  - Bash(bd:*)
  - Bash(git:*)
  - Bash(systemctl:*)
  - Bash(launchctl:*)
  - Bash(ssh:*)
  - Read
---

# bd-doctor

## Purpose

Health check and deterministic recovery for Beads coordination and backend health.

This skill assumes:
- active Beads runtime: `~/.beads-runtime/.beads`
- agent coordination surface: `bdx` (routes coordination commands over Tailscale SSH to epyc12)
- backend: Dolt server mode on `epyc12`
- multi-host operation (macmini/epyc12/epyc6/homedesktop-wsl)

## When To Use

- `bd` commands fail with connection/lock errors
- dispatch preflight fails at Beads gate
- host summaries diverge (`beads-dolt status --json` mismatch)
- agent reports stalled/blocked Beads operations

## Quick Check

Run from any non-application directory:

```bash
export BEADS_DIR="${BEADS_DIR:-$HOME/.beads-runtime/.beads}"

bdx dolt test --json
bdx show <known-beads-id> --json
```

For backend-only diagnostics (service/listener/runtime consistency), use `beads-dolt` directly:

```bash
beads-dolt dolt test --json
beads-dolt status --json
```

`bdx ready --json` can still be slow on high-latency hosts for tight loops. Treat slow broad readiness queries as responsiveness degradation, not immediate evidence the backend is down.

Fail-fast signatures (treat as misconfiguration, not recovery path):
- `sqlite3: unable to open database file`
- `unknown command "dolt" for "bd"`
- `beads.role not configured` — local config drift, not a hub outage

Immediate response:

```bash
export PATH="$HOME/.local/bin:$PATH"
export BD_BIN="$HOME/.local/bin/bd"
export BEADS_DIR="$HOME/.beads-runtime/.beads"
hash -r
~/.agent/skills/health/bd-doctor/check.sh
```

Service checks:

Linux (hub host):
```bash
systemctl --user is-active beads-dolt.service
```

macOS:
```bash
if launchctl print gui/$(id -u)/com.starsend.beads-dolt >/dev/null 2>&1; then
  echo "⚠️ macOS launchd Beads service is present; this should remain disabled on control-pane hosts."
fi
```

## Recovery Playbooks

### 1) Dolt server unreachable

1. Restart managed service

Linux (hub host):
```bash
systemctl --user restart beads-dolt.service
```

macOS:
```bash
if launchctl print gui/$(id -u)/com.starsend.beads-dolt >/dev/null 2>&1; then
  launchctl bootout gui/$(id -u)/com.starsend.beads-dolt
  launchctl disable gui/$(id -u)/com.starsend.beads-dolt
fi
```

2. Re-validate:

```bash
beads-dolt dolt test --json
beads-dolt status --json
```

### 2) Lock contention (`database ... is locked by another dolt process`)

- Ensure one Dolt server process per host for `~/.beads-runtime/.beads/dolt` (hub only)
- Stop unmanaged process and restart managed service

Linux logs:
```bash
journalctl --user -u beads-dolt.service -n 100 --no-pager
```

macOS logs:
```bash
if [[ -f ~/.beads-runtime/.beads/dolt-launchd.err.log ]]; then
  tail -n 100 ~/.beads-runtime/.beads/dolt-launchd.err.log
fi
```

### 3) Host divergence (different totals across VMs)

1. Choose source host (default `epyc12`)
2. Stop source + target services
3. Copy source `~/.beads-runtime/.beads/dolt` to target
4. Restart services
5. Compare summaries on all hosts
6. Use this only when service-level failover or backup restore is unavoidable.

### 4) `beads.role` not configured (local config drift)

**Signature:** `bd` commands warn `beads.role not configured` or appear to hang on mutations (e.g., `bd create`), while `bd --version` and `beads-dolt dolt test --json` succeed.

**Root cause:** Local `beads.role` is unset. The Beads CLI requires this config to determine mutation permissions. This is host-local config drift, not a Dolt hub or service outage.

**Deterministic fix:**

```bash
bd config set beads.role maintainer
# If outside a Git repo and the command reports git config exit 128:
git config --global beads.role maintainer
```

**Verify after fix:**

```bash
beads-dolt dolt test --json   # should still pass
bd create --title "test" --type task --dry-run  # should proceed without role warning
```

**Rule:** Retry `bd config set beads.role maintainer`, then `git config --global beads.role maintainer` if needed, before escalating to hub/service diagnostics. If `beads-dolt dolt test --json` passes, the hub is healthy — the blocker is local.

### 5) `bd ready --json` slow or timing out on `macmini`

**Signature:** `bd show <known-id> --json` succeeds and `beads-dolt dolt test --json` passes, but broader commands like `bd ready --json` feel hung or exceed orchestration timeouts.

**Classification:** Query responsiveness degradation on the local host. Not a hub outage.

**Response:**

```bash
beads-dolt dolt test --json
beads-dolt show <known-beads-id> --json
```

**Rule:** On `macmini`, do not use `bd ready --json` as a health probe in tight loops. Use targeted `bd show <known-beads-id> --json` for responsiveness checks, and run broad queue inspection manually or from the hub host when needed.

### 6) Spoke connectivity from non-hub host

```bash
ssh -o BatchMode=yes epyc12 "hostname"
bdx dolt test --json
```

### 7) Bad/corrupt data dir

```bash
# Linux example
systemctl --user stop beads-dolt.service
cd ~/.beads-runtime/.beads
mv dolt dolt.bad.$(date +%Y%m%d%H%M%S)
# restore known-good snapshot into ./dolt
systemctl --user start beads-dolt.service
beads-dolt dolt test --json && beads-dolt status --json
```

## Fleet Verification (from macmini)

```bash
export BEADS_DOLT_SERVER_PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
export EPYC12_BEADS_HOST="${EPYC12_BEADS_HOST:-${BEADS_DOLT_SERVER_HOST:-100.107.173.83}}"

ssh epyc12 "bdx dolt test --json"
ssh homedesktop-wsl "bdx dolt test --json"
ssh epyc6 "bdx dolt test --json"
```

## Guardrails

- Use `bdx` as the canonical Beads coordination command surface for agents.
- Direct remote Dolt SQL is backend/service plumbing, not the agent coordination path.
- Do not rely on app-repo `.beads` directories for fleet Beads operations.
- Prefer `BEADS_DIR=~/.beads-runtime/.beads` and run control-plane commands from `$HOME` or `~/.beads-runtime`, not from app repositories.
- Do not run ad hoc `dolt sql-server` during active waves.
- Prefer managed services (`systemd --user` or `launchd`) for uptime.
- Use `beads-dolt dolt test --json` + `beads-dolt status --json` as source of truth.
- Do not infer Beads runtime health from `~/bd` git cleanliness.
- Use raw `bd` only for local diagnostics/bootstrap/path-sensitive operations or explicit override.

## Dolt truth guardrail (required)

Run this first when diagnosing issue visibility or data drift:

```bash
~/agent-skills/scripts/beads-truth-guard
```

When Dolt mode is reported, do not use these files as live truth:

- `$HOME/.beads-runtime/.beads/issues.jsonl`
- `$HOME/.beads-runtime/.beads/backup/issues.jsonl`
- `~/bd/.beads/issues.jsonl` (legacy/rollback mirror)
- `~/bd/.beads/backup/issues.jsonl` (legacy/rollback mirror)

Use live checks instead:

- `bdx show <id> --json`
- `bdx list --json`
- `beads-dolt status --json`
