# DX Fleet Spec — V7 (Canonical Worktrees + Durable Beads + Stable QA Paths)
**Status:** Active  
**Audience:** humans + all canonical IDE agents (`codex-cli`, `codex desktop`, `claude code`, `antigravity`, `gemini-cli`, `opencode`)  
**Last updated:** 2026-02-03  

## Purpose (What V7 Optimizes For)
V7 is a **fleet operating contract** for a solo founder running many agents across multiple VMs.

Primary goals:
- **Minimize founder cognitive load**: fewer WIP branches, fewer untracked artifacts, fewer “where did the work go?” incidents.
- **Maximize durability**: agent work should not be lost to VM resets, stale branches, or tool divergence.
- **Make the happy path obvious**: agents should not “fight the system”; guardrails should funnel them.

Non-goals:
- Invent new architecture. V7 is operational hardening of the existing worktree-first model.

## Core Concepts (Definitions)
**Canonical clone**: the repo at `~/<repo>` (e.g. `~/prime-radiant-ai`). It is a stable, shared baseline and should remain clean/on trunk.  
**Workspace**: a git worktree under `/tmp/agents/<id>/<repo>` where all real work happens.  
**Beads planning repo**: `~/bd` — a dedicated git repo that stores the Beads database at `~/bd/.beads` and syncs across VMs.  

## V7 Invariants (These Must Always Be True)
### I1 — No work in canonical clones
For canonical repos:
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

Rules:
- Canonical clones must stay **clean** and on **trunk** (`master` in this fleet).
- Any code/docs/config change happens in a **worktree workspace**.

Enforcement:
- Pre-commit hook blocks committing in canonical clones.
- `canonical-sync.sh` is a safety net (keeps canonical clones aligned daily).

### I2 — Worktree-only development
Happy-path command:
```bash
dx-worktree create <beads-id-or-task-id> <repo-name>
cd /tmp/agents/<beads-id-or-task-id>/<repo-name>
```

Rules:
- Prefer `dx-worktree` (do not run `git worktree ...` directly).
- One work item = one workspace = one branch = one PR.

### I3 — Single safety layer (DCG-only)
All agents use **DCG** as the standardized command safety layer.
- Avoid redundant/competing safety hooks that cause false positives and “agent fights”.
- If you see `git_safety_guard.py`, treat it as deprecated and remove it.

### I4 — Beads is durable and centralized
All Beads state lives in **one place**:
```bash
export BEADS_DIR="$HOME/bd/.beads"
```

Durability requirements:
- `~/bd` is a **git repo** with remote `stars-end/bd` (`origin` configured).
- All VMs sync `~/bd` regularly (`ru sync stars-end/bd`) and export frequently (`bd sync --no-daemon`).

If `bd doctor` reports **Repo Fingerprint mismatch**:
```bash
cd ~/bd
printf 'y\n' | bd migrate --update-repo-id
```

### I5 — Product repos must never track `.beads/`
For product repos (`prime-radiant-ai`, `affordabot`, `llm-common`):
- `.beads/` is **gitignored** and not tracked.
- Any workflow that relied on `.beads/**` must be disabled or migrated to `BEADS_DIR`.

### I6 — QA story paths are canonical (no “lost STORIES”)
The uismoke runner currently loads stories **non-recursively**.

Canonical story layout in app repos:
```
docs/TESTING/STORIES/poc/         # small deterministic P0/P1 “gate” stories
docs/TESTING/STORIES/production/  # flat directory of runnable production flows
docs/TESTING/stories_hybrid/      # analysis artifacts ONLY (README must say so)
```

Contract:
- **Only** `docs/TESTING/STORIES/{poc,production}` are runnable by default targets.
- Any “analysis-only” story sets must include a README that says they are not runnable.

## Why the “lost STORIES” saga happened (Root Cause)
What happened operationally:
- Rewritten production stories were placed under `docs/TESTING/stories_hybrid/` (a subdirectory).
- The uismoke loader is **non-recursive**, so those stories were effectively “invisible” to standard runs.
- Because multiple agents were working across VMs/branches, the directory mismatch created the impression that work was lost even though it existed.

V7 fixes this by:
- Defining the **only runnable locations** (`docs/TESTING/STORIES/poc` + `docs/TESTING/STORIES/production`).
- Requiring that any “non-runnable” sets are explicitly labeled as such (README).
- Standardizing Makefile targets to point to the canonical directories (see next section).

## Happy Path (End-to-End)
### 0) Preflight
```bash
dx-check
```
Expected:
- canonical clones clean on `master`
- `BEADS_DIR` points to `~/bd/.beads`
- `~/bd` has `origin` remote (or `dx-check` fails)
- auto-checkpoint scheduler active

### 1) Pick work (Beads-first)
```bash
bd list --status=open | head
bd show <id>
```

### 2) Create workspace and do work
```bash
dx-worktree create <id> <repo>
cd /tmp/agents/<id>/<repo>
```

Work:
- implement changes
- run the smallest verification needed (unit/lint/targeted checks)

### 3) Land the work (no stranded work)
```bash
git add -A
git commit -m "feat: ..."  # include Feature-Key / Agent / Role trailers if required by repo policy
git push -u origin <branch>
gh pr create --draft
```

### 4) Close the loop
- Convert PR from draft when ready, merge, delete branch.
- Clean up workspace:
```bash
dx-worktree cleanup <id>
```

## Keeping Agents on the Happy Path (Mechanisms)
### Guardrails (hard)
- Canonical commit blocks (pre-commit).
- `dx-check` fails if Beads isn’t durable (no `stars-end/bd` remote).
- DCG blocks destructive commands and encourages safer alternatives.

### Guardrails (soft)
- `ru sync` keeps canonical clones fresh and reduces drift.
- `auto-checkpoint` provides a safety net so agents don’t lose work if interrupted.
- QA contract targets (`verify-gate`, `verify-prod`, `verify-nightly`) reduce “where do I run this?” ambiguity.

### Psychological / agent-UX
- “Do X, don’t do Y” rules must be short and discoverable in `AGENTS.md`.
- Prefer one primary command per workflow step (`dx-worktree`, `dx-check`, `bd sync`, `ru sync`).
- Avoid multiple overlapping safety systems (they cause false positives and agents “fight” the process).

## Standard Verification Targets (App Repos)
App repos must provide:
- `make verify-gate`: deterministic P0 gate (fast)
- `make verify-prod`: production story suite (remote dev)
- `make verify-nightly`: full regression (poc + production), sequential if loader is non-recursive

Reference contract:
- `llm-common/docs/MAKE_CONTRACT.md`
- `llm-common/docs/QA_CONTRACT.md`

## Fleet Rollout Checklist (per VM)
1. Pull agent-skills and run health check:
   ```bash
   cd ~/agent-skills && git pull origin master
   dx-check
   ```
2. Ensure Beads repo exists and is synced:
   ```bash
   cd ~/bd && git pull --rebase
   bd doctor
   bd sync --no-daemon
   ```
3. Ensure cron/schedulers:
   - `ru sync` (all repos)
   - `ru sync stars-end/agent-skills`
   - `ru sync stars-end/bd`
   - `bd sync --no-daemon` (for `~/bd`)
   - auto-checkpoint timer active
4. Ensure product repos are V7-compatible:
   - `.beads/` not tracked, gitignored
   - `.beads`-dependent workflows disabled or migrated to `BEADS_DIR`
   - DCG-only (no legacy git safety guards)

## Appendix: Canonical Repo List
- `~/agent-skills` — fleet baseline + workflows + skills
- `~/prime-radiant-ai` — product app
- `~/affordabot` — product app
- `~/llm-common` — shared libs (uismoke harness + contracts)
- `~/bd` — Beads planning repo (durable shared DB)

