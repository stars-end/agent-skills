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
5. **Clean up** - Clear stashes, prune branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL**: Work is NOT complete until `git push` succeeds.
