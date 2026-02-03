# V5 Fleet Iteration v6 (P0)

**Goal:** minimize founder cognitive load while running many agents across **3 VMs × multiple IDEs** by enforcing a single durable workflow:
- canonical clones are **read-only + trunk + clean**
- all real work happens in **git worktrees** (`/tmp/agents/...`)
- Beads uses **external DB** (`BEADS_DIR=~/bd/.beads`)
- Beads runs in **direct mode** in worktrees (`bd --no-daemon` or `BEADS_NO_DAEMON=1`)
- auto-checkpoint is **rescue-only** and produces **one rolling PR per host**
- `ru sync` is “boring hygiene” on canonical clones only (autostash should become rare)

This iteration is tracked in Beads: `bd-fleet-v5-hardening.1` (children `.1`–`.9`).

---

## Fleet Contract (Non-Negotiables)

### 1) Canonical clones are not for doing work

Canonical directories:
- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

Invariant:
- `git status` in each canonical clone is **clean**
- current branch is **trunk** (usually `master`)

All coding/editing/commits happen in worktrees:
```bash
dx-worktree create bd-xxxx prime-radiant-ai
cd /tmp/agents/bd-xxxx/prime-radiant-ai
```

### 2) Beads uses external DB (no repo-local `.beads/`)

Fleet env:
```bash
export BEADS_DIR="$HOME/bd/.beads"
```

Beads upstream documents that when `BEADS_DIR` points to a different git repo, `bd sync` commits/pushes **there**, not in your code repo (see `~/beads/docs/WORKTREES.md`).

### 3) In worktrees, Beads daemon is unsafe by default

Beads upstream warns daemon mode can commit/push to the wrong branch in worktree-heavy setups unless you opt-in to specific modes (see `~/beads/docs/GIT_INTEGRATION.md`).

Fleet default for agent sessions:
```bash
export BEADS_NO_DAEMON=1
# or run individual commands with: bd --no-daemon <cmd>
```

### 4) auto-checkpoint is rescue-only

auto-checkpoint exists to prevent work loss when agents disobey (dirty canonicals / wrong branches).

Contract:
- checkpoints changes into `auto-checkpoint/<host>`
- best-effort push
- maintains **one rolling draft PR per host**
- restores canonical clone back to trunk at end

### 5) `ru sync` is canonical hygiene only

`ru` is built around keeping a projects directory updated; its README explicitly says: **never create worktrees/clones in the projects dir → use `/tmp/`** (repo_updater has no `docs/` dir; the canonical documentation is `~/repo_updater/README.md` + the `ru` script).

Fleet contract:
- `ru sync` runs against canonical clones (`~/repo`)
- `ru sync` must never operate under `/tmp/agents`
- autostash should be rare once canonicals remain trunk+clean

---

## Option A (Primary): Block canonicals, don’t “auto-fix”

**What happens if an agent tries to commit in a canonical repo:**
- the commit is blocked
- the error message is **ultra-clear** and gives a single correct next action
- the event is logged/countable to measure repeated non-compliance

Success looks like:
- agents quickly learn “always work in /tmp/agents”
- canonicals stay clean
- auto-checkpoint becomes a safety net, not the normal path

Tracked as: `bd-fleet-v5-hardening.1.1` + `bd-fleet-v5-hardening.1.2`.

---

## Week-1 Evaluation Gate (7 days)

Tracked as: `bd-fleet-v5-hardening.1.2` (gates Option B).

### Metrics to collect (per VM host)
- number of blocked canonical commit attempts (should trend down)
- number of auto-checkpoint commits/day (should trend down)
- number of rolling PRs open (goal: **≤ 1 per host per repo**)
- stash count trend in canonicals (goal: flat or down)
- count of non-trunk canonical incidents detected by dx-check/dx-status

Decision rule:
- If agents are repeatedly “fighting” the block and metrics don’t improve → activate Option B fallback plan.

---

## Option B (Backup after week-1): Auto-branch + rolling PR per host

Tracked as: `bd-fleet-v5-hardening.1.9` (depends on week-1 evaluation).

Design intent:
- accept that some agents will not comply
- make canonical commits “safe enough” by immediately moving them off trunk and into a **single rolling PR per host**

Key requirements (to avoid a return to PR chaos):
- do **not** create a new PR per commit
- do **not** auto-close PRs while still active
- ensure a predictable lifecycle (cleanup with clear rules)

Operational risks:
- pre-commit doing network (`git push`, `gh pr`) can fail offline / without auth
- surprising automation may confuse agents and humans
- needs strong logging/observability to avoid silent failure

---

## Work Items (Beads mapping)

- `bd-fleet-v5-hardening.1.1`: Option A enforcement (block + message + log)
- `bd-fleet-v5-hardening.1.2`: week-1 metrics + decision gate
- `bd-fleet-v5-hardening.1.3`: Beads policy (external DB + no-daemon default)
- `bd-fleet-v5-hardening.1.4`: agent-skills skills cleanup (remove `.beads/issues.jsonl` workflows)
- `bd-fleet-v5-hardening.1.5`: product repo context skill updates (context-dx-meta)
- `bd-fleet-v5-hardening.1.6`: ru contract + cron ordering (avoid stash explosions)
- `bd-fleet-v5-hardening.1.7`: auto-checkpoint contract (rescue-only + rolling PR per host)
- `bd-fleet-v5-hardening.1.8`: keep this doc as the “vs+1” increment artifact

---

## AGENTS.md / Baseline Tree Adjustments

This iteration requires the AGENTS.md compilation tree to explicitly encode:
- worktree-only development (canonicals are planning surfaces)
- external Beads (`BEADS_DIR`) and the implication that `bd sync` doesn’t touch code repos
- worktree-safe Beads usage (`BEADS_NO_DAEMON=1` or `bd --no-daemon`)
- ru contract (canonicals only; never `/tmp/agents`)
- auto-checkpoint semantics (rescue-only; 1 rolling PR per host)

The highest leverage fix is to remove legacy skill guidance that talks about committing `.beads/issues.jsonl` inside product repos.

