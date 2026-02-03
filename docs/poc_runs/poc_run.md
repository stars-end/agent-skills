# Fresh-Agent POC Run

**Date**: 2026-02-03
**Agent**: Claude Code (glm-4.7)
**Purpose**: Test DX flow for fresh agents using only auto-provided context

## Auto-Provided Context Discovery

### File Inventory
```
-rw-r--r--@ 1 fengning  staff  20763 Feb  3 06:54 AGENTS.md
lrwxr-xr-x@ 1 fengning  staff      9 Feb  1 09:12 GEMINI.md -> AGENTS.md
```

**Key finding**: `GEMINI.md` is a symlink to `AGENTS.md` - single source of truth.

### Canonical Repository Rules (Extract)
```
60:## ⚠️ CANONICAL REPOSITORY RULES (CRITICAL)
69:1. ❌ **NEVER commit directly to canonical repos**
71:3. ✅ **ALWAYS use worktrees for any change** (code, docs, config, etc.)
76:# Start new work - ALWAYS use worktrees
```

## Git State at Session Start
```
Repo root:   /Users/fengning/agent-skills
Branch:      master
Git status:  (clean - no output from --porcelain=v1)
```

## Reflections

### What Confused Me
- **Initial instinct violation**: I almost started writing files directly to the canonical repo before catching myself. The safety guard hook helped, but it was a close call.
- **GEMINI.md symlink discovery**: Had to run `ls -la` to understand it wasn't a separate file. For a fresh agent, this could be confusing - why have two names if they're the same?
- **Worktree pattern ambiguity**: The rules say "ALWAYS use worktrees" but don't specify the pattern. Had to infer `/tmp/agents/{branch-name}` from the examples.

### What Went Smoothly
- **Single source of truth**: AGENTS.md is comprehensive - everything needed was in one place.
- **rg search worked**: Found the canonical rules quickly with the provided search pattern.
- **git-safety-guard triggered**: The hook showed "state recovery..." message, providing feedback that protections are active.
- **Clean repo state**: Starting from `master` with clean status meant no conflicts to resolve before starting work.

### What Would Reduce Founder Cognitive Load
1. **Worktree command as T0 proceed**: The rules say "use worktrees" but don't provide the exact command. Suggest adding:
   ```bash
   dx-worktree create poc-test agent-skills  # Auto-creates /tmp/agents/poc-test/agent-skills
   ```
   This would eliminate the need to remember/construct `git worktree add -b <branch> <path>`.

2. **GEMINI.md rationale**: Brief comment explaining why the symlink exists (e.g., "# Symlink for IDE compatibility - Gemini agents expect GEMINI.md").

3. **Session start checklist**: AGENTS.md has a "Session Start Bootstrap" section but it's 7 steps long. Consider a "60-second version":
   ```bash
   dx-check              # 1. Verify environment
   git pull origin master # 2. Sync repo
   # Done - ready to work
   ```

4. **Safety guard feedback**: When git-safety-guard blocks or triggers, show WHAT it protected against, not just "state recovery". Example:
   ```
   [git-safety-guard] ✓ Protected: Detected canonical repo write attempt
   [git-safety-guard] Hint: Use 'dx-worktree create <branch> <repo>' instead
   ```

5. **POC deliverable template**: The prompt asked for specific file outputs but didn't provide a template. Consider adding `docs/poc_runs/template.md` for consistency.

## POC Conclusion

The DX flow is **functionally complete** - all information needed is present and discoverable. The friction points are around **pattern discovery** (how to construct worktree paths/commands) rather than missing information.

**Recommendation**: Add "T0 proceed" examples for common patterns (worktree creation, environment check) so agents don't need to infer from prose.
