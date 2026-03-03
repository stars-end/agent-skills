---
name: beads-guard
description: |
  Safe Beads workflow helper (warning-only). Use before bd sync/close/create to
  avoid Beads conflict. Ensures you are on a feature branch, up to date with
  origin/master, and executes Beads operations against the canonical `~/bd` Dolt backend.
tags: [beads, dx, guardrail]
---

# Beads Guard

Avoid Beads drift and master commits with canonical Dolt backend checks.

## How to run (manual steps)

```bash
# 0) Must be on a feature branch (not master)
git status -sb

# 1) Rebase to latest master
git fetch origin master
git rebase origin/master

# 2) Verify Beads connectivity (server mode)
cd ~/bd && bd dolt test --json
# If this fails, run `bd-doctor` before proceeding
cd -

# 3) Do your Beads op in canonical repo context
cd ~/bd
export BEADS_DIR="$HOME/bd/.beads"
export BEADS_IGNORE_REPO_MISMATCH=1
#   bd close <id> --reason "..."
#   bd create "..." --type ... --priority ...
#   bd sync

# 4) Return and commit code changes only
cd -

# 5) Commit with Feature-Key trailer (on feature branch)
git commit -m "beads: <summary>\n\nFeature-Key: <id>\nAgent: claude-code\nRole: backend-engineer"

# 7) Push/PR as normal
git push
```

## Notes
- Warning-only flow; no hard blocks.
- If branch is behind master and Beads changed, rebase before committing.
- Keep Beads ops off master to avoid hook warnings.
