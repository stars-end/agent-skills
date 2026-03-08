---
name: session-end
description: |
  End Claude Code session with Beads health verification and summary. MUST BE USED when user says they're done, ending session, or logging off.
  Verifies canonical Beads connectivity, shows session stats, and suggests next ready work. Handles cleanup and context saving.
  Use when user says "goodbye", "bye", "done for now", "logging off",
  or when user mentions end-of-session, session termination, cleanup, context saving,
  Beads checks, Dolt status, or export operations.
tags: [workflow, beads, session, cleanup]
allowed-tools:
  - mcp__plugin_beads_beads__*
  - Bash(bd:*)
  - Bash(git:*)
---

# Session End

End session cleanly with Beads health checks, stats, and next work suggestion.

## Workflow

### 1. Set Beads Context
```
mcp__plugin_beads_beads__set_context(workspace_root="/path/to/project")
```

### 2. Verify Canonical Beads Health
**CRITICAL:** confirm Beads is reachable before ending session context.

```bash
beads-dolt dolt test --json
beads-dolt status --json
```

**What this does:**
- Confirms Dolt server connectivity
- Confirms issue summary is queryable
- Prevents silent session-end on broken tracker state

### 3. Get Session Stats
```
stats = mcp__plugin_beads_beads__stats()
```

Show relevant metrics:
- Issues closed this session
- Issues created this session
- Current epic progress
- Total ready work available

### 4. Suggest Next Work
```
readyTasks = mcp__plugin_beads_beads__ready(priority=1)
```

Show top 3-5 ready tasks by priority:
- Unblocked P1 issues
- Next phase tasks in current epic
- High-value backlog items

### 5. Verify Canonicals Are Clean (V7.6)

Run the invariant check before claiming you're “done”:

```bash
~/agent-skills/scripts/dx-verify-clean.sh
```

### 6. Context Summary

Show what to resume in next session:
```
📊 Session Summary

Issues Closed: 3
  • bd-xpi.4 (Testing)
  • bd-xpi.4.1 (Bug: SessionStart permission)
  • bd-xpi.4.2 (Bug: UserPromptSubmit JSON)

Issues Created: 2
  • bd-xpi.4.1 (discovered-from bd-xpi.4)
  • bd-xpi.4.2 (discovered-from bd-xpi.4)

Current Work:
  bd-xpi.5 (in_progress): Implementation Part 2
  Epic: bd-xpi (DX_V3_BEADS_INTEGRATION)

✅ Beads connectivity verified
✅ Canonicals verified clean

📍 Next Session:
  Top ready tasks:
  1. bd-xpi.5 (P1) - Continue implementation
  2. bd-abc.3 (P1) - API integration testing
  3. bd-def.2 (P2) - Documentation updates

Say "bd ready" to see full ready work queue
```

## Best Practices

- **Always call at session end** - Catches tracker outages before context loss
- **Don't skip health checks** - Prevents silent drift on broken Beads service
- **Review stats** - Understand what was accomplished
- **Note next work** - Reduces context switching overhead in next session
- **Git status clean** - Commit all work before session-end

## Common Usage

**User signals:**
- "I'm done for today"
- "Ending session"
- "Log off"
- "Save and exit"
- "That's all for now"

> Note: Skill activation relies on semantic description matching, not legacy pattern files.

## What This DOESN'T Do

- ❌ Create new issues (use beads-workflow for that)
- ❌ Commit code (use sync-feature-branch first)
- ❌ Close ongoing work (only validates state + summarizes)

**Philosophy:** Clean exits + Context preservation + Ready for next session
