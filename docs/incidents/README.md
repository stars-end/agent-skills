# Infrastructure Incident: Beads Database Lock Recovery

**Date**: 2026-03-05
**Status**: Active
**Priority**: P0 (Blocking)
**Impact**: All Beads MCP operations failing

## Summary

Beads issue tracking system is completely non-functional due to stale database lock. Both daemon and direct modes fail, blocking all issue tracking and workflow automation.

## Quick Links

- **Diagnostic Report**: [2026-03-05-beads-lock-recovery.md](./2026-03-05-beads-lock-recovery.md)
- **EODHD Fix Plan**: Related implementation plan pending Beads recovery

## Impact

- ❌ Cannot create/track issues
- ❌ Cannot query work status
- ❌ Workflow automation blocked
- ✅ Manual workarounds available (markdown plans)

## Root Cause

Stale `noms LOCK` file from unclean shutdown blocking database access.

## Recovery Status

- [ ] Diagnosed
- [ ] Lock removed
- [ ] Service restarted
- [ ] Validated

## Assignee

Infrastructure/DevOps agent with Dolt + Beads expertise
