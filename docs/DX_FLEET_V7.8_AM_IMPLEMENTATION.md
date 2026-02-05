# DX Fleet V7.8 (A–M) — Implementation Spec (JR-Agent Executable)
Date: 2026-02-05  
Status: Implementation-ready  
Owner: fengning  

This document is the **implementation companion** to `docs/DX_FLEET_SPEC_V7.8_AM.md`.

Purpose:
- Give a junior agent a deterministic runbook to implement and validate each V7.8 A–M workstream.
- Ensure LLM agents can verify compliance using a **repeatable evidence bundle** (commands + expected outputs).

Hard constraints:
- **NO WRITES in canonical clones**: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`
- **Worktree first**: `dx-worktree create <id> <repo>`
- **Before “done”**: `~/agent-skills/scripts/dx-verify-clean.sh` must PASS

---

## 0) Evidence Bundle (required for all workstreams)

For any task you claim complete, capture:

```bash
# Canonical hygiene gate
~/agent-skills/scripts/dx-verify-clean.sh

# Worktree + WIP snapshot
~/agent-skills/scripts/dx-status.sh | tail -40

# If relevant (cross-VM)
~/agent-skills/scripts/dx-fleet-check.sh
```

If the workstream touches Clawdbot:

```bash
lsof -nP -iTCP:18789 -sTCP:LISTEN
clawdbot cron status
clawdbot cron list --all --json | head -200
```

---

## 1) Workstreams A–M (mapping to Beads)

The operating spec maps letters to epics/tasks:
- A–J: existing V7.8 epics: `bd-l99g`, `bd-636z`, `bd-pf4f`, `bd-z3pu`
- K: `bd-e0tp` (Beads durability + backlog hygiene)
- L: `bd-4n6b` (Founder inbox + heartbeat)
- M: `bd-w8p6` (Fleet registry + helpers)

This doc focuses on **implementation steps + acceptance**. The canonical source of truth for priorities/dependencies is Beads.

---

## 2) L (Founder inbox + heartbeat) — Implementation Checklist

### 2.1 Files (repo changes)
Must exist in `agent-skills` (worktree only):
- `scripts/dx-inbox.sh`
- `configs/fleet_hosts.yaml`
- `scripts/dx-fleet-check.sh`
- `scripts/bd-sync-safe.sh` (if adopting K as part of L; otherwise keep K separate)

Acceptance:
- `scripts/dx-inbox.sh` is read-only and prints:
  - **exactly one line** when healthy
  - **<= 6 lines** when not healthy
- `scripts/dx-fleet-check.sh` is read-only and:
  - prints local host report
  - prints remote host warnings but **does not exit early**
- `configs/fleet_hosts.yaml` includes macmini/homedesktop-wsl/epyc6 (ssh target + login shell).

### 2.2 Clawdbot setup (macmini captain)
Preconditions:
- Slack delivery configured in Clawdbot.
- Gateway running persistently.

Steps:
1) Ensure gateway is listening:
   - `lsof -nP -iTCP:18789 -sTCP:LISTEN`
2) Create (or ensure) an agent workspace:
   - workspace recommended: `~/clawd-all-stars-end`
3) Create two cron jobs (delivered to Slack channel `#all-stars-end`):
   - Pulse: 06:00–16:00 PST every 2 hours
   - Daily review: 05:00 PST daily

Critical requirement:
- Cron jobs MUST pin provider/model explicitly (fleet default: **ZAI GLM-4.7**).
- The gateway must have ZAI credentials available (either via Clawdbot auth profiles or `ZAI_API_KEY` in the gateway environment).

Acceptance:
- `clawdbot cron list --all --json` shows both jobs enabled.
- Jobs can run via `clawdbot cron run <id> --force` and deliver to Slack.

---

## 3) M (Fleet registry + helpers) — Implementation Checklist

### 3.1 Fleet host registry
File:
- `configs/fleet_hosts.yaml`

Acceptance:
- Contains:
  - `ssh` target
  - `shell` (fleet standard: `zsh`)
  - notes about captain VM

### 3.2 Cross-VM check helper
File:
- `scripts/dx-fleet-check.sh`

Acceptance:
- Works when SSH is available.
- If a host is unreachable, prints a warning and continues.

---

## 4) Final validation (before merging PR)

In the worktree:
```bash
./scripts/dx-inbox.sh
./scripts/dx-fleet-check.sh || true
```

In the canonical clone:
```bash
~/agent-skills/scripts/dx-verify-clean.sh
```

PR must only include the intended files (no accidental tool artifacts).
