# DX Fleet Spec V7.8 (A–M) — Operating System
Date: 2026-02-05  
Owner: fengning  
Scope: macmini + homedesktop-wsl + epyc6; repos: `agent-skills`, `prime-radiant-ai`, `affordabot`, `llm-common`  
Slack Heartbeat Channel: `#all-stars-end`  

This document consolidates the current DX fleet operating model across all layers (host-plane automation, repo-plane baseline inheritance, PR-plane visibility, and Beads planning) and the additional “A–M” workstreams.

The core problem this system solves:
- Work became **hidden** (stashes, WIP branches, orphan worktrees, unpushed commits) → founder context switching and archaeology.
- The fleet needs to convert hidden state into **bounded visible state** (PR inbox + short daily inbox).

---

## 0) Definitions

### Canonical clone
The read-mostly clone in `~/<repo>`:
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

### Workspace / worktree
All real work happens in an isolated worktree under:
- `/tmp/agents/<id>/<repo>`

Worktrees are created using `dx-worktree` (do not use `git worktree` directly).

### External Beads DB
Beads state is centralized and shared across VMs:
- `BEADS_DIR="$HOME/bd/.beads"`
- Repo-local `.beads/` directories in product repos are forbidden.

### PR-plane visibility
“If it doesn’t have a PR, it’s not real work.”  
V7.8 enforces that any WIP becomes visible via draft PRs or (rare) rescue PRs.

---

## 1) Invariants (MUST / MUST NOT)

### 1.1 Canonical rules
- MUST keep canonicals on `master`.
- MUST keep canonicals clean (`git status --porcelain` empty).
- MUST NOT commit in canonicals.
- MUST NOT stash in canonicals (hidden state).

### 1.2 Worktree rules
- MUST create a worktree before making any repo change:
  - `dx-worktree create <id> <repo>`
- MUST push worktree commits to origin.
- MUST ensure a draft PR exists for any branch with meaningful work.

### 1.3 “Done gate”
Before claiming “done” on any task:
- MUST pass: `~/agent-skills/scripts/dx-verify-clean.sh`
- MUST ensure PR(s) exist for all changes.

---

## 2) Planes of the system (what runs where)

### 2.1 Host-plane automation (runs on VMs)
These scripts run locally (cron/systemd/launchd) to keep hygiene bounded:
- `dx-sweeper` (canonical rescue → rolling rescue PR; then restore canonical)
- `dx-janitor` (worktree PR surfacing; push no-upstream; create draft PR)
- `dx-worktree-gc` (safe delete/archive of stale worktrees)
- `dx-status` (fleet snapshot)
- `dx-triage-cron` (worktree-safe triage gating artifacts)
- `ru sync` (repo updater; canonical-only)
- `auto-checkpoint` (safety net only; not a delivery mechanism)

### 2.2 Repo-plane baseline inheritance (runs in GitHub Actions)
Product repos inherit `agent-skills` baseline:
- `baseline-sync.yml` (rolling draft PR updating `fragments/universal-baseline.md` + regenerated `AGENTS.md`)
- `verify-agents-md.yml` (CI freshness check)
- `scripts/agents-md-compile.zsh` + `make regenerate-agents-md`

### 2.3 PR-plane (GitHub)
The founder inbox should be bounded to:
- baseline-sync draft PRs (one per product repo, rolling branch)
- a small number of active feature PRs
- rescue PRs: one rolling rescue PR per host+repo (rare)

### 2.4 Beads-plane (planning)
Beads is the persistent work graph:
- Epics and tasks live in external DB (`~/bd/.beads`).
- All V7.8 workstreams map to epics with child tasks and dependencies.

---

## 3) Scripts (authoritative entry points)

All scripts referenced below live in `~/agent-skills/scripts/`.

### 3.1 `dx-verify-clean.sh` (hard “done” gate)
Purpose:
- Fail fast if any canonical repo is dirty or off trunk.
- Fail if canonical stashes exist (hidden state).

Usage:
- Run before claiming completion: `dx-verify-clean`

Expected output:
- PASS: all canonicals clean + on `master`
- FAIL: explicit repo(s) + remediation hints

### 3.2 `dx-status.sh` (snapshot)
Purpose:
- Show totals + exceptions:
  - Total worktrees
  - Dirty stale worktrees
  - No-upstream worktrees
  - auto-checkpoint health

Usage:
- `dx-status`

Rule:
- Treat `Dirty (Stale)` and `No Upstream` as the two main hygiene signals.

### 3.3 `dx-sweeper.sh` (canonical rescue)
Purpose:
- If canonical repo violates invariants (dirty / off trunk / stashes), rescue to PR-plane then restore canonical.

Core safety properties:
- Never reset canonical until the rescued work is durable (pushed and PR exists).
- Uses a rolling rescue PR per host+repo to avoid PR explosion.

### 3.4 `dx-janitor.sh` (worktree PR surfacing)
Purpose:
- Ensure worktrees don’t become hidden local state.
- For any worktree with commits:
  - push branch (including no-upstream branches)
  - ensure a draft PR exists (or reuse existing)

Safety:
- Non-destructive by default.
- Avoids duplicate PR creation.

### 3.5 `dx-worktree-gc.sh` (cleanup/GC)
Purpose:
- Keep `/tmp/agents` from ballooning.

Policy:
- SAFE DELETE only if:
  - worktree clean
  - branch merged to master
  - cooldown elapsed
- ARCHIVE is copy-based (tarball) before deletion paths are considered.

---

## 4) Schedules (conservative by default)

This section defines the intended schedule. Actual rollout must be done per VM and verified.

### 4.1 Schedule ordering (important)
Reason:
- Avoid conflicts between rescue and “hard reset” safety nets.

Recommended daily order:
1) `dx-sweeper` (canonical rescue; create rolling PR if needed)
2) `dx-worktree-gc` (cleanup)
3) `canonical-sync.sh` (safety net alignment)

### 4.2 Janitor cadence (business hours)
Recommended:
- Run `dx-janitor` 2× daily during business hours to keep PR-plane visibility.

### 4.3 External Beads DB sync cadence
Use `bd-sync-safe.sh` wrapper (Group K) so `~/bd` stays git-clean and durable.

---

## 5) Clawdbot heartbeat (founder attention UX)

### 5.1 Philosophy
Heartbeat is the “attention router”, not the hygiene actor.
- Heartbeat runs read-only checks and posts a bounded report.
- Hygiene scripts do the actual cleanup (janitor/sweeper/gc) via scheduled host-plane automation.

### 5.2 Heartbeat channel
Slack channel: `#all-stars-end`.

### 5.3 Heartbeat modes
We run two heartbeat modes:

1) **Pulse** (every 2 hours during working hours):
- Purpose: keep attention tight and bounded; detect drift early.
- Output: **one line when OK**; short exception list when not OK.

2) **Daily compliance review** (once per day):
- Purpose: a meta-evaluation against the intended V7.8 happy path:
  - “Given the last 24h evidence, list every deviation from the V7.8 intended workflow.”
- Output: one line when OK; otherwise a short list of deviations + severity + next actions.
- Escalation: if egregious, include `@fengning`.

### 5.4 Heartbeat schedule (captain VM only)
To avoid duplicates, **only macmini** is the heartbeat captain.

Pulse window (PST):
- Start: **06:00**
- End: **16:00**
- Cadence: **every 2 hours** (06, 08, 10, 12, 14, 16).

Daily compliance review (PST):
- Runs at **05:00** and covers the prior 24 hours.

### 5.5 Heartbeat payload contracts

#### Pulse payload
Collect (read-only):
- Local: `dx-verify-clean` + `dx-status` (and/or `dx-inbox` once it exists)
- Optional cross-VM: `dx-fleet-check` (read-only SSH), but only if it stays fast/reliable.

Output:
- OK: **exactly one line** with a short summary (no multi-line dumps).
- Not OK: still bounded; list only top exceptions + a “next command”.

#### Daily compliance review payload
This is not a status update; it is a compliance audit:

Input evidence bundle should include:
- For each VM (via SSH):
  - canonical hygiene (branch/dirty/stash counts)
  - `dx-status` metrics (worktree roots, dirty-stale list, no-upstream list)
  - last-run timestamps for: `ru sync`, `canonical-sync`, `auto-checkpoint`, `dx-janitor`, `dx-sweeper`, `dx-worktree-gc`
- GitHub PR-plane:
  - rescue PRs created/updated in last 24h
  - baseline-sync PRs created/updated
- Beads-plane (optional):
  - top “next” pick via BV (e.g. `bv --robot-next`)

Prompt (conceptual):
> “Here is the V7.8 intended happy path. Given the last 24h evidence bundle, tell me everything that didn’t follow this.”

Output:
- OK: **exactly one line**.
- Not OK: list deviations grouped by (Host-plane / Repo-plane / PR-plane / Beads-plane), with severity.

### 5.6 Egregious escalation (silent failure awareness)
If any of these happen, the daily review (and sometimes pulse) should include `@fengning`:

Canonical integrity:
- Any canonical repo is dirty or off trunk.
- Any canonical stash exists (hidden state).

Durability / lost-work risk:
- Rescue PR updated/created (means canonical rules were violated).
- No-upstream worktrees persist >24h (work at risk of being stranded).
- Worktree count spikes above threshold (e.g. >30).

Automation failure (silent drift):
- Expected schedule did not run (janitor/sweeper/gc/ru sync/canonical-sync) within its expected window.
- External Beads repo (`~/bd`) is git-dirty after scheduled sync (durability regression).
- Heartbeat not delivered (gateway down, main queue stuck, channel routing misconfigured).

### 5.7 Background process vs heartbeat (OpenClaw gateway)
Use the two tools intentionally:

- **Heartbeat**: periodic, bounded turns in the agent session; best for short read-only checks + attention routing.
- **Background process (`exec`/`process`)**: best for longer-running audit tasks; can be configured to notify on exit by enqueuing a system event that requests a heartbeat.

Recommended pattern:
- Pulse = heartbeat only (fast).
- Daily review = run the evidence collector as a background exec, then deliver the summary via heartbeat.

### 5.8 Heartbeat implementation notes (current state)
On macmini (captain VM), Clawdbot runs via the local gateway (loopback):
- Gateway: `ws://127.0.0.1:18789`
- Cron jobs store: `~/.clawdbot/cron/jobs.json`

Verification (macmini):
```bash
# Gateway is listening
lsof -nP -iTCP:18789 -sTCP:LISTEN

# Cron scheduler health + jobs
clawdbot cron status
clawdbot cron list --all --json
```

Provider note:
- Heartbeat jobs MUST pin the model/provider explicitly (fleet standard: **ZAI GLM-4.7**).
- If jobs omit `--model`, Clawdbot may default to another provider (e.g. Anthropic) and fail auth unexpectedly.
- Ensure `ZAI_API_KEY` is available to the **gateway process environment** (launchd/systemd shells may not inherit your interactive shell env).

Contract reminder:
- Heartbeat posts to `#all-stars-end`.
- Heartbeat runs read-only commands only (no cleanup actions).

---

## 6) BV integration (Beads acceleration)

BV is already available locally (`bv --help`).

### 6.1 Founder “what next” standard
Recommended minimal commands:
- `bv --robot-next` (single next best action)
- `bv --robot-triage-by-track` (tracks view for parallelization)

### 6.2 Fleet recipe/workspace (planned)
Define a BV workspace or recipe that scopes to DX fleet epics so the heartbeat can embed a short “Beads next”.

---

## 7) Workstreams A–M (epic map)

This section maps the workstreams to Beads epics. IDs are tracked in the external DB.

### A–J (existing V7.8 epics)
- Host-plane activation + cross-VM hygiene: `bd-l99g`
- DX Audit dashboard + optional LLM triage: `bd-636z`
- GitHub Actions cleanup + standardization: `bd-pf4f`
- Beads-first workflow + dx-worktree alignment: `bd-z3pu`

### K (new): Beads durability + backlog hygiene
- Epic: `bd-e0tp`
  - Ensure `~/bd` is git-clean after scheduled sync
  - Close/supersede legacy DX epics so `bd ready` reflects current work

### L (new): Founder inbox + heartbeat
- Epic: `bd-4n6b`
  - Implement `dx-inbox` (read-only)
  - Integrate into Clawdbot heartbeat in `#all-stars-end`
  - Optional: on-demand “/dx” commands (confirm-first)

### M (new): Fleet registry + helpers
- Epic: `bd-w8p6`
  - `configs/fleet_hosts.yaml`
  - `dx-fleet-check.sh` read-only cross-VM report

---

## 8) Tight feedback loop (mistakes → improvements)

### 8.1 What we have today
Signals:
- `dx-status` highlights hygiene exceptions (dirty stale, no-upstream).
- `dx-verify-clean` gates “done”.
- PR-plane: baseline-sync drafts show repo-plane inheritance is working.

### 8.2 What’s missing (to tighten the loop)
We need a durable “mistake capture → action item” path:
- When an agent leaves hidden state (dirty stale, no-upstream, stash), it should be:
  1) surfaced in the heartbeat
  2) converted into a Beads task (auto or semi-auto)
  3) optionally triaged by an LLM on GitHub (labels/comments only)

### 8.3 GitHub Actions (planned)
DX audit is tracked under `bd-636z`:
- Deterministic collector posts a rolling DX audit issue.
- Optional LLM triage layer adds labels/comments (no destructive actions).
- Allowlisted auto-merge reduces baseline-sync review load (bounded scope).

---

## 9) Current known hygiene exceptions (macmini snapshot)
At time of writing, macmini `dx-status` reports:
- Dirty (Stale): 1
  - `/tmp/agents/bd-pr-triage/agent-skills`
- No Upstream: 2
  - prime-radiant-ai worktrees (paths listed in `dx-status`)

These are the canonical “feedback loop” test cases: they should become visible, get resolved, and then stop recurring.

---

## 10) Non-goals
- This spec does not attempt to solve multi-agent file contention inside a single repo beyond worktrees.
- This spec does not require additional global instruction files per IDE; the repo-plane baseline + tiny rails should be sufficient.

---

## 11) Implementation runbook (jr-agent executable)

This section is intentionally concrete. It is the “do this, then test that” version of the spec.

### 11.1 Prerequisites (macmini captain)
- Captain VM: **macmini only** (other VMs MUST NOT send heartbeat messages to Slack).
- Slack: Clawdbot Slack channel must be configured and able to deliver messages.
- Repos: canonical clones exist under `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`.
- Beads external DB: `BEADS_DIR="$HOME/bd/.beads"` and `~/bd` has a git remote.

### 11.2 Required scripts to implement (agent-skills)
This spec assumes these scripts exist (they are tracked as workstreams K/L/M):

K — Beads durability:
- `scripts/bd-sync-safe.sh` (wrapper): runs `bd sync` then commits/pushes `~/bd` if dirty.

L — Founder inbox:
- `scripts/dx-inbox.sh` (read-only): bounded output, one-liner when healthy.

M — Fleet helpers:
- `configs/fleet_hosts.yaml` (authoritative list of canonical VMs + ssh targets)
- `scripts/dx-fleet-check.sh` (read-only): runs `dx-verify-clean` + `dx-status` on all VMs and prints a short report.

### 11.3 Clawdbot wiring (macmini)
We implement pulse + daily review via Clawdbot cron jobs delivered to Slack.

#### 11.3.1 Ensure an isolated agent exists for `clawd-all-stars-end`
This creates a dedicated “DX ops” agent identity and workspace.

Recommended:
```bash
clawdbot agents add all-stars-end --workspace ~/clawd-all-stars-end --non-interactive
clawdbot agents list --json
```

#### 11.3.2 Pulse cron (06:00–16:00 PST, every 2h)
Run in an **isolated** session by default (keeps long-running main sessions clean).

Recommended:
```bash
clawdbot cron add \
  --name dx-pulse \
  --description "DX pulse heartbeat (V7.8) — one line when OK" \
  --agent all-stars-end \
  --session isolated \
  --wake next-heartbeat \
  --cron "0 6-16/2 * * *" \
  --tz "America/Los_Angeles" \
  --thinking low \
  --model "zai/glm-4.7" \
  --message "Deterministic heartbeat (do NOT guess). If ~/agent-skills/scripts/dx-inbox.sh is missing: output exactly one line 'DX PULSE BLOCKED (agent-skills missing dx-inbox.sh; merge agent-skills#113 and pull)' and stop. Otherwise run ~/agent-skills/scripts/dx-inbox.sh and output its result verbatim. Do not run destructive actions." \
  --deliver \
  --channel slack \
  --to "#all-stars-end" \
  --best-effort-deliver
```

#### 11.3.3 Daily compliance review cron (05:00 PST)
This is an evaluation against the intended happy path.

Recommended:
```bash
clawdbot cron add \
  --name dx-daily \
  --description "DX daily compliance review (last 24h) — V7.8 deviations only" \
  --agent all-stars-end \
  --session isolated \
  --wake next-heartbeat \
  --cron "0 5 * * *" \
  --tz "America/Los_Angeles" \
  --thinking low \
  --model "zai/glm-4.7" \
  --message "Deterministic daily review (do NOT guess). If ~/agent-skills/scripts/dx-fleet-check.sh is missing: output exactly one line 'DX DAILY BLOCKED (agent-skills missing dx-fleet-check.sh; merge agent-skills#113 and pull)' and stop. Otherwise run ~/agent-skills/scripts/dx-fleet-check.sh and use it as evidence; if available also include bv --robot-next one-line summary. If no deviations, output exactly one line starting with 'DX DAILY OK'. If deviations, list them grouped by plane with severity; include @fengning only if egregious per spec §5.6. Do not run destructive actions." \
  --deliver \
  --channel slack \
  --to "#all-stars-end" \
  --best-effort-deliver
```

Notes:
- These cron jobs are intended to replace ad-hoc notification scripts.
- Hygiene actions remain deterministic and separate (janitor/sweeper/gc schedules), not performed by heartbeat jobs.
 - Create/enable these jobs only after `agent-skills` has the scripts on `master`; otherwise they should produce `DX *_BLOCKED` and stop.

### 11.4 Host-plane hygiene schedules (all VMs)
This spec assumes V7.8 hygiene jobs are scheduled per VM (tracked in `bd-l99g`):
- `dx-sweeper` daily before `canonical-sync`
- `dx-worktree-gc` daily
- `dx-janitor` business hours
- `ru sync` canonical-only
- `auto-checkpoint` remains safety net only

---

## 12) Testing & validation

### 12.1 Script-level tests (macmini)
Run locally:
```bash
~/agent-skills/scripts/dx-verify-clean.sh
~/agent-skills/scripts/dx-status.sh
~/agent-skills/scripts/dx-inbox.sh
```

Expected:
- `dx-verify-clean` PASS when healthy.
- `dx-status` prints explicit paths for exceptions.
- `dx-inbox` prints **one line** when healthy.

### 12.2 Clawdbot tests (macmini)
Verify cron jobs exist and run history is recorded:
```bash
clawdbot cron list
clawdbot cron runs --json | head
```

Trigger a manual run:
```bash
clawdbot cron run --name dx-pulse
clawdbot cron run --name dx-daily
```

Expected:
- Slack message delivered to `#all-stars-end`.
- When healthy: exactly one line.

### 12.3 Failure-injection tests (safe)
These tests validate that the daily review finds deviations.

1) Create a no-upstream worktree with a commit (safe):
- Create worktree, commit, do not push.
- Run `dx-status` and confirm `No Upstream` > 0.
- Run `dx-pulse` → should report exception.

2) Create a stale dirty worktree (safe):
- Add an untracked file in a worktree.
- Wait >4h or simulate stale by removing any session lock.
- Run `dx-status` → should report Dirty (Stale).
- Run `dx-daily` → should list deviation.

3) Simulate schedule drift:
- Temporarily disable `dx-janitor` schedule on a non-captain VM.
- Daily review should report “expected schedule did not run”.
