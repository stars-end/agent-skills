# Railway Integration Implementation Plan

**Document Version:** 1.0.0
**Feature Branch:** `feature-railway-integration`
**Epic:** bd-railway-integration
**Created:** 2025-01-12

---

## Overview

This document provides the complete implementation plan for integrating Railway's official agent skills patterns into the agent-skills registry.

**Goal:** Enable Railway deployment with pre-flight validation across all AI coding agents (Claude Code, Codex CLI, OpenCode, Gemini CLI, Antigravity).

---

## Quick Reference

### What We're Building

```
┌─────────────────────────────────────────────────────────────┐
│                    BEFORE                                    │
├─────────────────────────────────────────────────────────────┤
│  Code → Deploy → Fail → Debug → Deploy → Fail → ...         │
│  (17% toil commits wasted on Railway deployment issues)     │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    AFTER                                     │
├─────────────────────────────────────────────────────────────┤
│  Code → railway-doctor check → Fix issues → Deploy → ✅     │
│  (<5% deployment failures, <30min fix time)                 │
└─────────────────────────────────────────────────────────────┘
```

### Skills to Modify

| Skill | Changes | Files |
|-------|---------|-------|
| railway-doctor | +5 validation functions | SKILL.md, check.sh, fix.sh |
| skill-creator | +Railway template | SKILL.md, resources/examples/ |
| devops-dx | +GraphQL validation | SKILL.md, scripts/validate_railway_env.sh |
| vm-bootstrap | +Railway checks | SKILL.md, verify.sh |
| verify-pipeline | +Railway stage | SKILL.md |
| multi-agent-dispatch | +Railway target | SKILL.md, scripts/dispatch/railway.sh |
| feature-lifecycle | +Railway prompt | SKILL.md, finish.sh |

---

## Implementation Phases

### Phase 1: Foundation (P0)

**Duration:** 1-2 hours

1. Create feature branch
2. Create lib/ directory structure
3. Add railway-api.sh and railway-common.sh
4. Test lib scripts

**Deliverables:**
- `feature-railway-integration` branch
- `lib/railway-api.sh` ✅ (Done)
- `lib/railway-common.sh` ✅ (Done)

---

### Phase 2: Core Skills (P0)

**Duration:** 3-4 hours

#### 2.1 railway-doctor Enhancements

**Add to check.sh:**
```bash
check_monorepo_root_directory()  # Detect isolated vs shared
check_command_conflict()         # buildCommand != startCommand
check_package_manager()          # packageManager matches lockfile
check_railway_token()            # GraphQL auth check
check_railway_config()           # railway.toml validation
```

**Update SKILL.md:**
- Add `allowed-tools: Bash(railway:*) Bash(curl:*)`
- Add "Composability" section
- Add "Agent Compatibility" section
- Add validation stages table

#### 2.2 skill-creator Railway Template

**Create:** `skill-creator/resources/examples/railway-integration-skill.md`

**Update SKILL.md:**
- Add "Platform Integration Skill" type
- Add Railway to skill type classification
- Add GraphQL pattern documentation

---

### Phase 3: Integration Skills (P1)

**Duration:** 2-3 hours

#### 3.1 devops-dx GraphQL Integration

**Create:** `devops-dx/scripts/validate_railway_env.sh`

**Update SKILL.md:**
- Add `Bash(curl:*)` to allowed-tools
- Add GraphQL query examples
- Add bulk validation section

#### 3.2 vm-bootstrap Railway Validation

**Update verify.sh:**
```bash
check_railway_cli_version()  # >= 3.0.0 required
check_railway_auth()         # railway login status
```

**Update SKILL.md:**
- Add Railway to required tools table
- Add Railway checks to agent guidance

---

### Phase 4: Workflow Skills (P2)

**Duration:** 1-2 hours

#### 4.1 verify-pipeline Railway Stage

**Update SKILL.md:**
- Add Railway verification stage table
- Add `make verify-railway` snippet

#### 4.2 multi-agent-dispatch Railway Target

**Create:** `multi-agent-dispatch/scripts/dispatch/railway.sh`

**Update SKILL.md:**
- Add Railway dispatch examples
- Add Slack notification pattern

#### 4.3 feature-lifecycle Railway Integration

**Update finish.sh:**
- Detect Railway deployment features
- Offer railway-doctor check

**Update SKILL.md:**
- Add Railway workflow note

---

### Phase 5: Testing & Documentation

**Duration:** 1-2 hours

1. Test all modified skills
2. Verify agent compatibility
3. Update AGENTS.md
4. Update CLAUDE.md
5. Create final summary

---

## File Changes Summary

```
agent-skills/
├── docs/
│   ├── RAILWAY_AGENT_COMPATIBILITY.md      ✅ (Done)
│   ├── RAILWAY_INTEGRATION_GUIDE.md        ✅ (Done)
│   ├── BEADS_RAILWAY_EPIC.md               ✅ (Done)
│   └── RAILWAY_IMPLEMENTATION_PLAN.md      → This file
│
├── lib/
│   ├── railway-api.sh                      ✅ (Done)
│   └── railway-common.sh                   ✅ (Done)
│
├── railway-doctor/
│   ├── SKILL.md                            → UPDATE
│   ├── check.sh                            → UPDATE
│   └── fix.sh                              → UPDATE
│
├── skill-creator/
│   ├── SKILL.md                            → UPDATE
│   └── resources/
│       └── examples/
│           └── railway-integration-skill.md → CREATE
│
├── devops-dx/
│   ├── SKILL.md                            → UPDATE
│   └── scripts/
│       └── validate_railway_env.sh         → CREATE
│
├── vm-bootstrap/
│   ├── SKILL.md                            → UPDATE
│   └── verify.sh                           → UPDATE
│
├── verify-pipeline/
│   └── SKILL.md                            → UPDATE
│
├── multi-agent-dispatch/
│   ├── SKILL.md                            → UPDATE
│   └── scripts/
│       └── dispatch/
│           └── railway.sh                  → CREATE
│
├── feature-lifecycle/
│   ├── SKILL.md                            → UPDATE
│   └── finish.sh                           → UPDATE
│
├── AGENTS.md                               → UPDATE
└── CLAUDE.md                               → UPDATE
```

---

## Testing Checklist

### Unit Tests

- [ ] railway-doctor check.sh runs without errors
- [ ] railway-doctor detects monorepo issues
- [ ] railway-doctor detects command conflicts
- [ ] railway-api.sh GraphQL queries work
- [ ] railway-common.sh functions export correctly

### Integration Tests

- [ ] railway-doctor passes on valid project
- [ ] railway-doctor fails on invalid config
- [ ] devops-dx validates Railway env
- [ ] vm-bootstrap detects Railway CLI
- [ ] multi-agent-dispatch Railway target works

### Cross-Agent Tests

- [ ] Scripts work on Claude Code (skills-native)
- [ ] Scripts work via MCP (universal-skills)
- [ ] Environment variable fallback works

---

## Success Criteria

All of the following must be true:

1. ✅ All 7 skills updated with Railway patterns
2. ✅ Lib scripts work on both agent types
3. ✅ railway-doctor catches monorepo issues
4. ✅ railway-doctor catches command conflicts
5. ✅ devops-dx GraphQL queries work
6. ✅ vm-bootstrap validates Railway CLI
7. ✅ Documentation is comprehensive
8. ✅ Tests pass on all modified skills

---

## Rollback Plan

If issues arise:

1. **Revert branch:** `git checkout master`
2. **Delete branch:** `git branch -D feature-railway-integration`
3. **Restore lib:** `rm -rf lib/railway-*.sh`

**Safe Operations:**
- Adding new functions (non-breaking)
- Adding new sections to SKILL.md (non-breaking)
- Creating new scripts (non-breaking)

**Potentially Breaking:**
- Modifying existing check.sh logic (additive only)
- Changing allowed-tools (expand, don't restrict)

---

## Related Documents

- [BEADS_RAILWAY_EPIC.md](./BEADS_RAILWAY_EPIC.md) - Complete epic details
- [RAILWAY_AGENT_COMPATIBILITY.md](./RAILWAY_AGENT_COMPATIBILITY.md) - Agent compatibility
- [RAILWAY_INTEGRATION_GUIDE.md](./RAILWAY_INTEGRATION_GUIDE.md) - User guide

---

## Version History

- **v1.0.0** (2025-01-12): Initial implementation plan
  - 5 phases defined
  - File changes mapped
  - Testing checklist created
  - Success criteria defined
