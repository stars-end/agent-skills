---
name: worktree-workflow
description: |
  Create and manage task workspaces using git worktrees (without exposing worktree complexity).
  Use this when starting work on a Beads ID, when an agent needs a clean workspace, or when a repo is dirty and blocks sync.
  Provides a single command (`dx-worktree`) for create/cleanup/prune and a recovery path via dirty-repo-bootstrap.
tags: [dx, git, worktree, workspace, workflow]
allowed-tools:
  - Bash(scripts/dx-worktree.sh:*)
  - Bash(scripts/worktree-setup.sh:*)
  - Bash(scripts/worktree-cleanup.sh:*)
  - Bash(dirty-repo-bootstrap/snapshot.sh:*)
---

# Worktree Workflow (Workspace-First)

## Goal

Keep canonical clones clean and on `master`, while agents do all work in isolated workspaces:

`/tmp/agents/<beads-id>/<repo>`

## Commands

### Create workspace (recommended default)

```bash
dx-worktree create <beads-id> <repo>
```

Returns a path you can `cd` into.

For Railway-linked repos, this also seeds `.dx/railway-context.env` and attempts a
non-interactive `railway link` in the worktree so `railway status` / `railway run`
work without falling back to canonical repo directories.

### Cleanup a task workspace

```bash
dx-worktree cleanup <beads-id>
dx-worktree prune <repo>
```

### Recovery if workspace is dirty and you need to switch

```bash
~/.agent/skills/dirty-repo-bootstrap/snapshot.sh
```

## Guidance for agents (simple rules)

- Never edit code in `~/<repo>` (canonical clones).
- Always work inside the returned workspace path.
- If stuck: snapshot → cleanup → recreate.

## Keep Your Work Safe

> **Policy (DX V8):** `auto-checkpoint` was removed — it conflicted with canonical pre-commit
> hooks. The replacement is: commit your work, `worktree-push.sh` pushes it nightly (3:15 AM),
> and `worktree-gc-v8.sh` prunes worktrees older than 48h. **Uncommitted work older than 48h
> is considered stale and will be GC'd. This is intentional.** Commit or lose it.

### Rules

- **Open a draft PR after your first real commit** — makes work visible before the 3:15 AM push
- **Commit at logical milestones** — not on a timer; `worktree-push.sh` handles the rest
- **Uncommitted changes are your responsibility** — no cron will save them
