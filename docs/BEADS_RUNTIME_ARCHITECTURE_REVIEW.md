# Beads Runtime Architecture Review

**Date:** 2026-04-07
**Author:** External systems consultant
**Beads upstream SHA:** 7f0a165f4e8e1315e909c1ea925481670d27bdee
**Epic:** bd-nywzd | **Task:** bd-nywzd.1
**Status:** Recommendation

---

## Executive Summary

The current local model uses `~/bd` — a full git checkout of `stars-end/bd` — as
both a git repository and the runtime anchor for Beads CLI operations.  Under
centralized Dolt server mode, this coupling is unnecessary, creates recurring
agent confusion, and adds cognitive load for the founder.

**Recommendation:** Adopt a dedicated, non-git Beads runtime directory using
upstream-native `BEADS_DIR` + `--stealth`.  This is the simplest change that
eliminates the root cause.

---

## 1  Problem Statement

`~/bd` currently serves three roles simultaneously:

| Role | What it means | Who cares |
|------|---------------|-----------|
| **Git checkout** | Clone of `stars-end/bd`, with branches, dirty state, commit history | Agents inspecting `git status` |
| **Runtime anchor** | `BEADS_DIR=$HOME/bd/.beads` — config, metadata, Dolt connection | `bd` CLI, workflow scripts |
| **Legacy artifact store** | `issues.jsonl`, backups, `.beads-hygiene-backups` | Nothing (stale under Dolt mode) |

Consequences observed in production:

1. Agents run `git status` in `~/bd` and misinterpret dirty/diverged state as
   Beads health failures.
2. Agents confuse git-level operations (`git pull`, `git checkout`) with Beads
   data sync (`bd dolt push/pull`).
3. The runbook, skill docs, and AGENTS.md all carry guardrails to prevent agents
   from reading stale `issues.jsonl` — guardrails that exist solely because the
   git checkout makes the file visible.
4. The `.beads/` directory in `~/bd` contains ~3 MB of legacy JSONL artifacts
   that are never the source of truth under Dolt server mode.
5. `beads.role` config drift produces warnings that look like service failures.

The root cause is architectural: two unrelated concerns (git repo state and
Beads runtime state) occupy the same directory, creating a large confusion
surface for agents that default to filesystem inspection.

---

## 2  Upstream Product Model

Beads upstream (as of 7f0a165) explicitly supports separating runtime from any
git repository.  Relevant product features:

### 2.1  `BEADS_DIR` environment variable

From README.md and REPO_CONTEXT.md:

```bash
export BEADS_DIR=/path/to/your/project/.beads
bd init --quiet --stealth
```

`BEADS_DIR` tells `bd` where to put the `.beads/` database directory, bypassing
git repo discovery entirely.  This is documented as the primary mechanism for
non-git VCS, monorepos, CI/CD, and evaluation environments.

### 2.2  Stealth mode (`--stealth`)

Sets `no-git-ops: true` in config, disabling all git hook installation and git
operations.  Combined with `BEADS_DIR`, this produces a pure runtime anchor with
zero git surface.

### 2.3  Server mode with `BEADS_DIR`

REPO_CONTEXT.md confirms that `BEADS_DIR` takes precedence over routing config
and is the primary resolution path for all `bd` commands.  Server mode config
(host, port, database name) lives in `.beads/config.yaml` and
`.beads/metadata.json`, both of which are already inside the `BEADS_DIR` path.

### 2.4  Shared server mode

DOLT.md documents `shared-server` mode at `~/.beads/shared-server/`, which is
essentially the pattern we want: Dolt server state that lives outside any git
repo and serves all projects via prefix isolation.

### 2.5  Git-free usage

README.md section "Git-Free Usage" explicitly documents:

> All core commands work with zero git calls

This confirms the product is designed to work without any git repository
involved.

**Summary:** Upstream Beads _wants_ you to use `BEADS_DIR` + `--stealth` when
the git repo is not the natural home for Beads state.  The centralized Dolt
server model is a textbook fit for this separation.

---

## 3  Options Analysis

### Option A: Dedicated non-git Beads runtime directory

**Model:** `BEADS_DIR` points at a non-checkout path (e.g., `~/.beads-runtime/`
or `~/.beads/bd/`).  No git repo involved.  Server-mode metadata and config
live there.

**What changes:**

- New directory: `~/.beads-runtime/.beads/` (or similar)
- `bd init --stealth --server` in that directory (one-time)
- Copy `config.yaml` and `metadata.json` from current `~/bd/.beads/`
- Set `BEADS_DIR=~/.beads-runtime/.beads` in all host profiles
- All workflow scripts, skill docs, and AGENTS.md reference `BEADS_DIR` instead
  of `~/bd`

**What stops:**

- No `git status` in Beads context — agents cannot confuse git hygiene with
  Beads health
- No stale `issues.jsonl` visible — agents cannot read legacy files
- No dirty/diverged repo state — nothing to diverge

**What does NOT change:**

- Dolt server stays on epyc12 at 100.107.173.83:3307
- `bd` CLI binary stays at `~/.local/bin/bd`
- All `bd show`, `bd list`, `bd create` commands work identically
- Workflow scripts (`beads-dolt`, `bd-context`, etc.) work — they already use
  `BEADS_DIR`
- The `stars-end/bd` git repo can still exist at `~/bd` for reference — it just
  stops being the runtime anchor

**Tradeoffs:**

| Pro | Con |
|-----|-----|
| Eliminates root cause of agent confusion | One-time migration (< 1 hour) |
| Removes all stale-file guardrails | Must update AGENTS.md, runbook, skill docs |
| Matches upstream-documented architecture | `~/bd` git checkout becomes orphan context |
| Zero ongoing cognitive load | — |

**Assessment:** This is the strongest option.  It aligns with upstream product
design, eliminates the confusion root cause, and requires minimal migration.

---

### Option B: Upstream-native multi-project / shared-server model

**Model:** Use Beads' `shared-server` mode at `~/.beads/shared-server/`.  Each
"project" (which is really just the workspace tracker) gets its own database
prefix.  No per-repo `.beads/` directory needed for the centralized tracker.

**What changes:**

- Enable `BEADS_DOLT_SHARED_SERVER=1` globally
- Run `bd init --prefix bd --shared-server` to register
- Shared server lives at `~/.beads/shared-server/`
- Set `BEADS_DIR=~/.beads/shared-server/.beads` or equivalent

**Problem:**

This model is designed for _multiple local projects sharing one local Dolt
server_.  Our fleet uses a _remote_ Dolt server on epyc12.  The shared-server
model starts a local Dolt process at `~/.beads/shared-server/`, which conflicts
with the remote-server architecture we already have.

**Assessment:** Not a fit.  The shared-server feature solves a different problem
(port conflicts between local projects).  Our architecture is remote-server
with spokes, which is already working correctly.  Adopting shared-server would
add a component we don't need and potentially conflict with the existing fleet
topology.

---

### Option C: Wrapper-only stabilization (keep `~/bd`)

**Model:** Keep `~/bd` as the runtime anchor.  Add stronger wrappers, readiness
gates, and agent behavior policies to prevent confusion.

**What changes:**

- Add pre-check scripts that suppress `git status` inspection in `~/bd`
- Add agent instructions to never run git commands in `~/bd`
- Add `.gitignore` entries to hide stale artifacts
- Strengthen workflow guardrails

**Problem:**

This is the current approach, and it has demonstrably failed to prevent
confusion.  The issue is not insufficient guardrails — it is that the operating
surface presents two contradictory signals (git repo state and Beads runtime
state) in the same directory.  No amount of policy documentation can fully
prevent an agent from running `git status` in a directory that contains a
`.git/` folder.

**Assessment:** Worst option.  Preserves the root cause and adds ongoing
maintenance burden for guardrails that have already proven insufficient.

---

## 4  Recommendation

**Adopt Option A: Dedicated non-git Beads runtime directory.**

### 4.1  Target model

```
~/.beads-runtime/
└── .beads/
    ├── config.yaml          # Dolt server connection (100.107.173.83:3307)
    ├── metadata.json        # Project identity + backend config
    ├── .beads-credential-key
    └── last-touched

# No .git/, no issues.jsonl, no backup dirs, no git branches
```

Environment on all hosts:

```bash
export BEADS_DIR="$HOME/.beads-runtime/.beads"
export BEADS_DOLT_SERVER_HOST=100.107.173.83
export BEADS_DOLT_SERVER_PORT=3307
```

### 4.2  Migration sequence

**Change first (one-time, < 1 hour):**

1. Create `~/.beads-runtime/.beads/` on all fleet hosts
2. Copy `config.yaml` and `metadata.json` from `~/bd/.beads/`
3. Run `bd init --stealth --server` (or validate existing config)
4. Set `BEADS_DIR` in all host profiles (`.zshrc`, `.bashrc`, systemd env)
5. Validate: `bd list --json`, `beads-dolt dolt test --json`
6. Update AGENTS.md, runbook, beads-workflow SKILL.md to reference new path

**Do not change yet:**

- Do not delete `~/bd` — keep for reference, just stop referencing it as runtime
- Do not change Dolt server configuration on epyc12
- Do not change `bd` binary location or version
- Do not change fleet topology (hub-spoke model)
- Do not change any workflow scripts beyond `BEADS_DIR` path references

### 4.3  Doc surface changes

| Document | Change |
|----------|--------|
| `AGENTS.md` §1.5 | Replace `~/bd` references with `$BEADS_DIR` |
| `docs/PRIME_RADIANT_BEADS_DOLT_RUNBOOK.md` | Update runtime pins, remove `~/bd` path refs |
| `core/beads-workflow/SKILL.md` | Update canonical contract to `BEADS_DIR` |
| Host profiles (all fleet) | Set `BEADS_DIR=~/.beads-runtime/.beads` |

### 4.4  Answer to key questions

**Do we need `~/bd` at all under centralized Dolt server model?**

No. Under centralized Dolt server mode, the `bd` CLI only needs:
1. A `config.yaml` with server connection details
2. A `metadata.json` with project identity
3. Network access to the Dolt server

None of these require a git repository. `~/bd` can remain as a passive
reference checkout but should not be the runtime anchor.

**What does upstream Beads most naturally want us to do?**

Use `BEADS_DIR` + `--stealth`. The product explicitly documents this pattern
for exactly our use case: "CI/CD — isolated task tracking without repo-level
side effects."

**Which option is best for robustness?**

Option A. It eliminates the confusion surface rather than guarding against it.

**Which option is best for low founder cognitive load?**

Option A. After migration, the founder never thinks about `~/bd` git state
again. The mental model becomes: "Beads is a service I talk to via `bd` CLI.
Its config lives in `~/.beads-runtime/`."

**Which option is best for low agent confusion?**

Option A. Agents cannot run `git status` on a directory with no `.git/`.
Agents cannot read stale `issues.jsonl` from a directory that doesn't contain
one.

---

## 5  Remaining Tradeoffs

Even after adopting Option A, these tradeoffs persist:

1. **Network dependency:** All `bd` commands still require network access to
   epyc12.  This is inherent to the centralized Dolt server model and is not
   changed by the runtime directory choice.

2. **Config drift:** `config.yaml` and `metadata.json` must stay consistent
   across fleet hosts.  This is already true today; Option A does not make it
   worse.

3. **`beads.role` drift:** Local config drift (`beads.role not configured`)
   will still occur.  The self-heal pattern (`bd config set beads.role
   maintainer`) remains necessary.

4. **`~/bd` orphan:** The git checkout at `~/bd` will become an orphan artifact.
   This is low-risk: it is a read-only reference clone and can be deleted later
   when the team is confident the migration is complete.

5. **Stale docs:** Any documentation or KI that references `~/bd` as the Beads
   anchor will need updating.  This is a one-time cost.

---

## 6  Decision Requested

This memo recommends **Option A (dedicated non-git Beads runtime directory)**
with the migration sequence in §4.2.

Cognitive load decision required:
- `ALL_IN_NOW` — Migrate to `~/.beads-runtime/` and update all docs
- `DEFER_TO_P2_PLUS` — Keep `~/bd` with current guardrails
- `CLOSE_AS_NOT_WORTH_IT` — Accept the recurring confusion cost

The long-term payoff bias favors `ALL_IN_NOW`: biting the bullet once (< 1
hour migration + doc updates) eliminates a recurring source of agent confusion
and founder cognitive load with no ongoing maintenance cost.
