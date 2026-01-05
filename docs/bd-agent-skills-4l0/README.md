# bd-agent-skills-4l0: Multi-Agent Slack Coordination

**Epic ID:** `bd-agent-skills-4l0`  
**Status:** In Progress  
**Last Updated:** 2026-01-04

---

## Overview

Multi-agent coordination system using Slack as the communication hub, OpenCode as the execution engine, and Git worktrees for filesystem isolation.

## The Golden Rule

> **Beads ID is the primary key that links everything:**
> `bd-xyz → worktree → thread → session`

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              SLACK                                          │
│  #affordabot-agents                                                        │
│  ├── User: @epyc6 bd-xyz implement the auth feature                       │
│  └── [epyc6]: Working on bd-xyz...                                         │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                      GATEWAY COORDINATOR                                    │
│                      (runs on epyc6)                                        │
│  1. Parse @mention → target host (epyc6, macmini, jules)                   │
│  2. Extract Beads ID (bd-xyz) → worktree path                              │
│  3. Create/resume OpenCode session                                         │
│  4. Track: { slack_thread → session_id → beads_id → worktree }            │
└─────────────────────────────────┬───────────────────────────────────────────┘
                                  │
       ┌──────────────────────────┼──────────────────────────┐
       │                          │                          │
       ▼                          ▼                          ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│    epyc6        │    │    macmini      │    │    jules        │
│   OpenCode      │    │   OpenCode      │    │   Cloud         │
│   :4105         │    │   :4105         │    │   CLI           │
│ Worktrees:      │    │ Worktrees:      │    │ (cloud)         │
│  └─ bd-xyz/     │    │  └─ bd-abc/     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Supporting Documents

| Document | Purpose |
|----------|---------|
| [TECH_SPEC.md](./TECH_SPEC.md) | Entity relationships, routing, worktrees, session lifecycle |
| [COMPONENT_STATUS.md](./COMPONENT_STATUS.md) | Current status of all 17 components |
| [FAULT_INVENTORY.md](./FAULT_INVENTORY.md) | Known bugs and fixes (C1-C4, H1-H4, M1-M4) |
| [JULES_INTEGRATION.md](./JULES_INTEGRATION.md) | Three-gate routing to Jules cloud |
| [DX_INTEGRATION.md](./DX_INTEGRATION.md) | dx-hydrate, dx-check, dx-doctor, dx-deploy |
| [VERIFICATION_PLAN.md](./VERIFICATION_PLAN.md) | Test scenarios and automation |

## Quick Start

```bash
# Check system health
dx-check

# Start coordinator (already running via systemd)
systemctl --user status slack-coordinator

# Post task to Slack
# @epyc6 bd-xyz implement the feature from spec
```

## Entity Relationships

| Entity | Identifier | Human Readable |
|--------|------------|----------------|
| Beads Issue | `bd-xyz` | Issue title |
| Git Worktree | `~/repo-worktrees/bd-xyz/` | Directory path |
| Slack Thread | `thread_ts` | Thread in channel |
| Slack Agent | `@epyc6` | Hostname-based |
| OpenCode Session | `ses_...` | (internal only) |

## Quick Reference (v26 Summary)

| Question | Answer |
|----------|--------|
| Can you resume sessions? | ✅ Yes, via `GET/POST /session/:id/message` |
| Parallel work? | ✅ Yes, up to 10 sessions per host |
| VM = Repo? | ❌ No, sessions can span repos |
| Default routing? | epyc6 when no @mention |
| Named workers? | P3 - deferred |

## Phased Implementation

### P1: Basic Host Routing ✅
- [x] Gateway coordinator on epyc6
- [x] @epyc6 routing (local)
- [ ] @macmini routing (via HTTP to macmini:4105)
- [x] Default to epyc6 if no mention
- [x] Display hostname in responses

### P2: Session Management 🔴
- [ ] Parse `session:ses_XXX` from message
- [ ] Resume existing sessions
- [ ] List active sessions command
- [ ] Session cleanup (auto-delete old)

### P3: Named Workers (Deferred) ⏸️
- [ ] @epyc6-workerA syntax
- [ ] Persistent named sessions
- [ ] Worker-specific context injection
- [ ] Worker affinity for repos

## Implementation Phases

| Phase | Status | Description |
|-------|--------|-------------|
| P0 | ✅ DONE | Worktree creation + session cwd |
| P1 | ✅ DONE | Multi-VM routing (@macmini, @epyc6) |
| P2 | ✅ DONE | dx-* integration |
| P3 | ✅ DONE | Agent-to-agent communication |
| P4 | ✅ DONE | Testing automation (11 unit + 6 E2E) |
| P5 | ✅ DONE | Jules three-gate routing |
| **P6** | 🔴 TODO | **Multi-VM Orchestration** (see [P6_MULTI_VM_ORCHESTRATION.md](P6_MULTI_VM_ORCHESTRATION.md)) |

### P6: Multi-VM Orchestration (NEW)

- [ ] P6.1: Create `~/.agent-skills/vm-endpoints.json` config
- [ ] P6.2: Implement `dx-dispatch` script
- [ ] P6.3: Add Slack audit to dispatches (dual-write pattern)
- [ ] P6.4: Test multi-VM routing (homedesktop, macmini, epyc6)
- [ ] P6.5: Integration tests for full orchestrator flow

