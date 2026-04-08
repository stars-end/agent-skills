---
name: beads-guard
description: |
  Safe Beads workflow helper (warning-only). Use before Beads mutations to
  avoid Beads conflict. Ensures you are on a feature branch, up to date with
  origin/master, and executes Beads operations against canonical `~/bd` control-plane context
  with runtime pinned at `~/.beads-runtime/.beads`.
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

# 2) Pin dedicated runtime + verify Beads connectivity (server mode)
export BEADS_DIR="${BEADS_DIR:-$HOME/.beads-runtime/.beads}"
beads-dolt dolt test --json
# If this fails, run `bd-doctor` before proceeding

# 3) Do your Beads op in canonical repo context
#   bd close <id> --reason "..."
#   bd create "..." --type ... --priority ...
#   For rollback-only compatibility (deprecated): bd-sync-safe

# 4) Commit with Feature-Key trailer (on feature branch)
git commit -m "beads: <summary>\n\nFeature-Key: <id>\nAgent: claude-code\nRole: backend-engineer"

# 5) Push/PR as normal
git push
```

## Notes
- Warning-only flow; no hard blocks.
- If branch is behind master and Beads changed, rebase before committing.
- Keep Beads ops off master to avoid hook warnings.
- Do not treat `~/bd` git status as runtime health; use `bd`/`beads-dolt` live checks.
