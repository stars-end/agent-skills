## Landing the Plane (Session Completion)

When ending a work session, MUST complete ALL steps:

1. **File issues** for remaining work
2. **Run quality gates** (if code changed)
3. **Update issue status**
4. **PUSH TO REMOTE** (MANDATORY):
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Verify canonicals are clean** (V7.6):
   ```bash
   ~/agent-skills/scripts/dx-verify-clean.sh
   ```
6. **Clean up** - Clear stashes, prune branches
7. **Verify** - All changes committed AND pushed
8. **Hand off** - Provide context for next session

**CRITICAL**: Work is NOT complete until `git push` succeeds.

### PR-or-It-Didn't-Happen (V7.6)

After landing the plane:
- Canonical work → Sweeper creates rescue PR automatically
- Worktree work → Ensure PR exists (Janitor will create draft if missing)
- No PR visibility = Work is invisible and at risk

See: `fragments/v7.6-mechanisms.md` for sweeper/janitor details
