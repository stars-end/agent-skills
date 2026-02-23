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

## Keep Your Work Safe (Backup Protocol)

> **Critical**: Worktrees at `/tmp/agents/…` have one automatic safety net:
> `worktree-push.sh` (cron 3:15 AM) pushes committed branches nightly.
> But **uncommitted changes are not protected**. You must commit before sleeping.
> The `AUTO_CHECKPOINT_IMPLEMENTATION.md` design exists but the cron is not installed.
> You are responsible for committing regularly.

### Mandatory pattern for any session > 30 min

**Step 1 — Open a draft PR after your first real commit (within the first hour)**

```bash
# After first meaningful commit:
gh pr create --draft --title "bd-<id>: [WIP] <description>" \
  --body "Work in progress. Draft — do not merge."
```

This creates a remote backup from hour 1. If your session dies, all pushed commits are safe.

**Step 2 — Checkpoint commit every ~60 min**

The `checkpoint:` prefix bypasses the Feature-Key/Agent hook enforcement:

```bash
git add -A
git commit -m "checkpoint: <brief description of current state>"
git push
```

This is not a "real" commit — it's a safety snapshot. Use it freely.

**Step 3 — Push frequently**

A commit that exists only locally is lost if the process dies. Always `git push` immediately
after any checkpoint commit.

### Cadence summary

| When | Action |
|------|--------|
| After first real commit | `gh pr create --draft ...` |
| Every ~60 min thereafter | `git commit -m "checkpoint: ..." && git push` |
| Before any risky operation | `git commit -m "checkpoint: pre-<op>" && git push` |
| At "done" | Convert draft PR to ready-for-review |

