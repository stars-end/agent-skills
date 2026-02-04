# DX Fleet Spec — V7.8 (Lifecycle + GC)

**Date**: 2026-02-04  
**Trunk**: `master` (fleet standard)  
**Extends**: `docs/DX_FLEET_SPEC_V7.7.md` (baseline inheritance)  
**Includes**: `docs/DX_FLEET_SPEC_V7.6.md` (enforcement: Sweeper/Janitor/done-gate)  
**Historical context**: `docs/DX_FLEET_SPEC_V7.md` (V7 invariants)

---

## 0) Why V7.8 Exists (Observed Failure Mode)

V7.6–V7.7 reduced “lost work”, but fleet state can still **balloon** and become costly to reason about:

- `/tmp/agents/**` worktrees accumulate (50+ is common in multi-agent fleets).
- “Hidden state” returns via canonical stashes and no-upstream worktrees.
- Nested git repos (e.g. `.venv/src/llm-common/.git`) confuse worktree discovery.
- Tool artifacts (notably `.ralph*`) inflate “dirty” signals.

V7.8 adds **deterministic lifecycle + garbage collection (GC)** so work stays:

- visible (PR inbox)
- bounded (worktrees don’t grow unbounded)
- safe (no destructive cleanup unless provably safe)

---

## 1) Goals / Non-Goals

### Goals
- **No hidden work**: if work exists, it becomes visible in the PR inbox (draft PRs) or explicit alerts.
- **Bounded WIP surface area**: worktrees do not grow unbounded over time.
- **Safe-by-default cleanup**: only auto-delete worktrees that are provably safe to delete.
- **Founder cognitive load reduction**: replace “archaeology” (stashes/branches/worktrees) with a small number of visible PR decisions.

### Non-Goals
- V7.8 does **not** make agents perfectly compliant (assumes some violations).
- V7.8 does **not** require LLM automation for core hygiene (LLM is optional triage only).

---

## 2) Canonical Terminology

- **Canonical clone**: `~/{agent-skills,prime-radiant-ai,affordabot,llm-common}`.
  - Must be **clean** and on **`master`**.
  - Read-only for agents (work happens in worktrees).
- **Workspace / worktree**: `/tmp/agents/<id>/<repo>`.
  - All code work happens here (including docs/config changes).
- **External Beads DB**: `$BEADS_DIR` (fleet standard: `$HOME/bd/.beads`).
  - Product repos must **not** track `.beads/**` in git.
- **PR-or-it-didn’t-happen**: if a workstream has commits, it must have a PR (draft is fine).

---

## 3) Fleet Invariants (Kept from V7.x)

### I1 — Canonical clones are read-only
- **MUST NOT** edit or commit in canonical clones.
- **MUST** use `dx-worktree create <id> <repo>` for any change.

### I2 — Canonical clones stay on `master` and clean
- **MUST** keep canonical clones on `master` and `git status` empty.
- Any deviation is an **error state**.

### I3 — External Beads DB only (V6)
- **MUST** use `BEADS_DIR=$HOME/bd/.beads`.
- **MUST NOT** track `.beads/**` in product repos.

### I4 — Repo-plane baseline inheritance (V7.7)
- Product repos vendor the universal baseline into `fragments/universal-baseline.md`.
- `AGENTS.md` is generated deterministically from fragments + repo context skills.

### I5 — “Done gate” is authoritative (V7.6)
- **Before claiming done**, run:
  - `~/agent-skills/scripts/dx-verify-clean.sh` (must pass).

---

## 4) V7.8 Components (New/Extended)

### 4.1 `dx-status` (visibility)
**Purpose**: one command that summarizes fleet hygiene:
- canonical health (branch + dirty)
- external Beads DB status
- worktree counts (total, dirty active/stale)
- no-upstream worktrees
- SAFE DELETE candidates (GC)

**Worktree discovery requirement**: do not confuse nested git repos (e.g. vendored repos, venvs) with `dx-worktree` roots.

### 4.2 `dx-verify-clean` (hard safety gate)
**Purpose**: enforce “no hidden state” before claiming work complete.

**MUST fail** if any canonical repo:
- is not on `master`
- has uncommitted changes
- has any stashes

This is the founder’s “green light” check.

### 4.3 `dx-sweeper` (canonical rescue)
**Purpose**: if a canonical clone becomes dirty/off-trunk/stashed, turn it into a **single visible PR event**, then restore canonical hygiene.

**Safety gates**:
- If `.git/index.lock` exists → skip (git op in progress).
- If `.dx-session-lock` is fresh → skip (active session).

**Durability rule**:
- **Never reset canonical** until a rescue branch is successfully pushed and a draft PR exists (if configured).

### 4.4 `dx-janitor` (worktree PR surfacing)
**Purpose**: ensure work in worktrees becomes visible/durable.

Deterministic behavior:
- Push branches that are ahead / have no upstream (when safe).
- Create draft PRs if no PR exists for that branch.
- Avoid duplicates (“quiet mode”: do nothing if PR already exists).

### 4.5 `dx-worktree-gc` (lifecycle + GC)
**Purpose**: safely reduce `/tmp/agents/**` over time.

V7.8 introduces deterministic buckets:

- **SAFE DELETE**:
  - worktree is clean
  - branch is merged to `master`
  - older than cooldown (default 24h)
  - deletion uses: `git -C ~/<repo> worktree remove -f <path>`
- **ARCHIVE (copy-based)**:
  - produces `~/.dx-archives/<timestamp>-<id>-<repo>.tar.gz`
  - leaves original worktree intact
- **ESCALATE**:
  - dirty worktree with no active session lock / stale
  - prints actionable list; does not delete

Tool-noise filtering:
- `.ralph*` artifacts are **ignored** for “dirty” classification.

---

## 5) Optional: “DX Audit” (GitHub Actions)

GitHub Actions cannot see VM-local `/tmp/agents/**`, but can audit the **PR-plane**:

- draft PR counts per repo
- rescue PR counts (should be rare / bounded)
- stale PRs (label candidates)

Optional LLM triage (low risk):
- comment + label classification only (no auto-merge by default)
- recommended to run in GitHub Actions (centralized infra)

**Local VM WIP (stashes/worktrees)** is handled by V7.8 scripts:
- `dx-status` / `dx-verify-clean` / `dx-worktree-gc`

---

## 6) Automation Contract (Cron + Actions) — How it Fits Together

### 6.1 GitHub Actions (repo-plane)
- `agent-skills`: publish baseline → `dist/universal-baseline.md` + `dist/dx-global-constraints.md`
- product repos: baseline-sync + verify-agents-md + agents-md-compile

### 6.2 VM cron (host-plane)
V7.8 assumes VM automation exists and **must not create hidden state**.

Recommended ordering (example):
- `02:00` Sweeper (rescue canonical error states)
- `03:00` canonical-sync (safety net reset)
- business hours: Janitor + GC (surface PRs, reduce worktree count)

Auto-checkpoint:
- safety net only; it must not be the delivery mechanism.
- V7.8 relies on Janitor + PR surfacing to prevent “lost WIP”.

---

## 7) Founder Workflow (Happy Path)

### Daily (≤ 2 minutes)
1. Check PR inbox (draft PRs are expected).
2. Merge/close the few that matter.
3. If anything feels “missing”, run `dx-status` then `dx-verify-clean`.

### For agents (must be easy)
1. Create worktree: `dx-worktree create <id> <repo>`
2. Work normally
3. Before claiming done: `dx-verify-clean`

---

## 8) Safety Properties (What prevents data loss)

| Mechanism | Prevents | How |
|---|---|---|
| `dx-verify-clean` | “claimed done but canonicals dirty” | hard fail |
| `dx-sweeper` | canonical drift + hidden stashes | rescue → push/PR → restore |
| `dx-janitor` | unpushed worktrees / no PR | push + draft PR |
| `dx-worktree-gc` | `/tmp/agents` balloon | safe-delete/archival/escalate |
| `.dx-session-lock` | sweeping mid-session | skip active |

---

## 9) Benchmark / Acceptance Criteria (V7.8 “Working”)

On any VM:
- `dx-verify-clean` passes.
- `dx-status` shows:
  - canonicals clean/on `master`
  - stashes = 0
  - “dirty stale” list is short and actionable
  - “no upstream” count is near 0 (or explicitly explained)

Across repos:
- baseline inheritance present (V7.7)
- `.beads/**` not tracked; BEADS_DIR configured (V6)

---

## 10) Rollout (Phased)

1. Manual run: `dx-status`, `dx-verify-clean`, `dx-janitor`, `dx-worktree-gc --dry-run`
2. Enable scheduled Janitor + GC (business hours)
3. Enable Sweeper before canonical-sync
4. Monitor PR creation rate; tune cooldowns/thresholds as needed

