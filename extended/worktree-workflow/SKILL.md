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

