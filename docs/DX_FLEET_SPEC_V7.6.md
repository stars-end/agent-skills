# DX Fleet Spec — V7.6 (V7.5 + Enforcement Layer)

**Date:** 2026-02-04  
**Trunk:** `master` (fleet standard)  
**Scope:** 3 canonical VMs × multi-IDE agent fleet

## 0) Why V7.6 Exists (Observed Failure Mode)

We repeatedly hit a P0 failure mode:
- **Work becomes non-durable** (not committed/pushed / no PR)
- **State becomes hidden** (stashes, local-only branches, auto-checkpoint branches)
- Founder cognitive load explodes (manual archaeology across VMs and IDEs)

V7.6 is built on a key lesson:

> **Documentation is not enforcement.** Under cognitive load, agents will sometimes ignore AGENTS.md even if they read it.

V7.6 keeps V7.5’s self-healing mechanisms, and adds **enforcement at boundaries + prompt discipline** so “done” cannot be claimed while work is stranded.

## 1) Invariants (MUST / MUST NOT)

### I1 — Canonicals Are No-Write

**Canonical clones** (automation-owned):
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

**MUST NOT:** edit files in canonical clones (even “infra/system/DX workflow work”).  
**MUST:** keep canonical clones clean on `master`.

### I2 — All Work Happens in Worktrees

**MUST:** use `dx-worktree create <id> <repo>` for any change.  
**MUST NOT:** run `git worktree ...` directly.

### I3 — PR-or-It-Didn’t-Happen

Work is “durable” only when:
- commits are pushed, AND
- a PR exists (draft is OK).

If there is no PR, work is treated as **at risk** and will be surfaced by automation.

### I4 — External Beads Database Only

**MUST:** all Beads state lives in the external Beads repo via:

```bash
export BEADS_DIR="$HOME/bd/.beads"
```

**MUST NOT:** track `.beads/` inside product repos.

## 2) Components (V7.5 Core, unchanged)

### 2.1 Canonical Sweeper (deterministic)

`~/agent-skills/scripts/dx-sweeper.sh`

Purpose:
- If a canonical clone is dirty or off-trunk, preserve work, make it visible, and restore canonical to clean `master`.

Key behaviors:
- **Preserve-before-reset**: push any feature branch commits before resetting canonical
- **Rolling rescue PR**: **one** rescue PR per `<host,repo>` (bounded inbox)
- **No comment spam**: update PR body only
- **Never reset if push fails**

### 2.2 Worktree Janitor (deterministic)

`~/agent-skills/scripts/dx-janitor.sh`

Purpose:
- Ensure worktree work is durable: push commits and create a draft PR if missing.

Key behaviors:
- Pushes even if branch has no upstream (`git push -u`)
- Does not close PRs or delete branches (conservative default)
- Optional: reports `wip:abandon` candidates after 72h (inform-only)

### 2.3 Canonical Clean Gate (deterministic)

`~/agent-skills/scripts/dx-verify-clean.sh`

Purpose:
- A single command that answers: “Are all canonicals clean + on trunk?”
- This is the primary enforcement gate for “done” claims.

## 3) Enforcement Layer (New in V7.6)

### 3.1 Enforcement MUST NOT rely on “Session Start/End”

Reality:
- Many IDEs don’t support session hooks consistently.
- Many agent sessions run for 48–72 hours.

Therefore:
- **We do not rely on session-start or session-end as enforcement.**
- Enforcement happens via:
  - deterministic background automation (Sweeper/Janitor), and
  - explicit “done gate” (`dx-verify-clean`) in agent instructions and prompts.

### 3.2 “Done Gate” Rule

**MUST:** Before an agent says “done / complete / implemented”, they must run:

```bash
~/agent-skills/scripts/dx-verify-clean.sh
```

If it fails:
- The agent must evacuate work to a worktree and open PR(s), or
- wait for Sweeper rescue PR (not recommended).

### 3.3 Complex Task Prompt Contract (Tech Lead Responsibility)

For multi-repo work or 3+ phases, every prompt MUST start with a hard header:

```text
HARD CONSTRAINTS (MUST FOLLOW BEFORE ANY IMPLEMENTATION)
1) Create worktree FIRST (dx-worktree). No writes in ~/... canonicals.
2) List worktrees you will create (repo + id).
3) List the draft PRs you will open (repo + branch).
4) You are not “done” until ~/agent-skills/scripts/dx-verify-clean.sh passes.
```

Rationale:
- This prevents “special-case thinking” (“infra work can happen in canonical”).
- It forces the agent to surface the workspace plan before tunneling into implementation.

### 3.4 Beads Integration (Reminder + Structure, not enforcement)

Beads is used to reduce ambiguity:
- **MUST:** if the task is non-trivial, create/use a Beads issue ID and use it as the worktree id.
- The worktree path becomes self-documenting:
  - `/tmp/agents/<beads-id>/<repo>`

Beads does **not** replace enforcement:
- Sweeper/Janitor + PR-or-it-didn’t-happen remains the durable mechanism.

## 4) Schedules (VM automation)

These schedules are implementation details; the invariant is: “canonicals wake up clean, and work never hides locally.”

Recommended baseline:
- **Sweeper**: daily at **02:00** (before canonical reset at 03:00)
- **Canonical reset** (`canonical-sync.sh`): daily at **03:00**
- **ru sync**: daily at **04:00**
- **Janitor**: hourly during working hours (e.g., 09:00–18:00)

## 5) Optional LLM PR Triage (GitHub Actions only)

LLMs MUST NOT push branches or mutate git state locally.

Optional triage can run as GitHub Actions:
- On PR open/update, classify:
  - `SAFE_TO_MERGE`
  - `NEEDS_REVIEW`
  - `ABANDON_CANDIDATE`
- Add labels and a single comment.
- Never closes PRs automatically unless explicitly approved later.

## 6) Rollout Plan (phased)

1) Land agent-skills changes (scripts + doc + baseline)
2) Manual runs on one VM
3) Enable Sweeper schedule
4) Enable Janitor schedule
5) Expand to other VMs

## 7) Non-Goals

- Perfect agent compliance via documentation alone
- Auto-merging feature work
- Complex file-level reservation systems for this layer

V7.6 aims for:
**bounded inbox, minimal archaeology, and durable work even under noncompliance.**
