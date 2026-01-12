# Railway Integration Epic

**Epic ID:** `bd-railway-integration`
**Priority:** P1 (High)
**Status:** Draft
**Created:** 2025-01-12
**Owner:** claude-code
**Related Docs:**
- [RAILWAY_AGENT_COMPATIBILITY.md](./RAILWAY_AGENT_COMPATIBILITY.md)
- [RAILWAY_INTEGRATION_GUIDE.md](./RAILWAY_INTEGRATION_GUIDE.md)

---

## Epic Description

Integrate Railway's official agent skills patterns into the agent-skills registry. Railway provides comprehensive deployment and management capabilities via the agentskills.io standard format. This epic ensures compatibility across skills-native agents (Claude Code, Codex CLI, OpenCode) and MCP-dependent agents (Gemini CLI, Antigravity).

### Business Value

- **Reduced deployment failures**: Pre-flight validation catches 80% of issues before deploy
- **Faster iteration**: GraphQL-based queries provide reliable operations
- **Cross-agent compatibility**: Works with all major AI coding agents
- **Better DX**: Clear composability between skills

### Success Metrics

| Metric | Baseline | Target | Measurement |
|--------|----------|--------|-------------|
| Railway deployment failures | 17% of toil commits | <5% | Beads analysis |
| avg. time to fix deploy issues | 2-3 hours | <30 min | Time tracking |
| Skills with Railway patterns | 0 | 7 affected skills | Skills inventory |
| Agent compatibility | Unknown | 100% documented | Compatibility matrix |

---

## Epic Structure

```
bd-railway-integration
├── bd-railway-integration.1  → railway-doctor enhancements (P0)
├── bd-railway-integration.2  → skill-creator Railway template (P0)
├── bd-railway-integration.3  → devops-dx GraphQL integration (P1)
├── bd-railway-integration.4  → vm-bootstrap Railway validation (P1)
├── bd-railway-integration.5  → verify-pipeline Railway stage (P2)
├── bd-railway-integration.6  → multi-agent-dispatch Railway target (P2)
├── bd-railway-integration.7  → feature-lifecycle Railway integration (P3)
└── bd-railway-integration.8  → Documentation and testing (P1)
```

---

## Child Tasks

### bd-railway-integration.1: railway-doctor Enhancements (P0)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 4-6 hours
**Dependencies:** None

**Description:**
Enhance railway-doctor skill with Railway official patterns: monorepo validation, build config checks, GraphQL support.

**Tasks:**
- [ ] Add `allowed-tools` declaration to frontmatter
- [ ] Implement `check_monorepo_root_directory()` function
- [ ] Implement `check_command_conflict()` function
- [ ] Implement `check_package_manager()` function
- [ ] Implement `check_railway_token()` function via GraphQL
- [ ] Add "Composability with Railway Official Skills" section
- [ ] Update examples with new validation stages
- [ ] Test on real Railway projects (affordabot, prime-radiant-ai)

**Definition of Done:**
- All validation functions working
- Tests pass on both isolated and shared monorepos
- Documentation updated with Railway official skill links
- Compatible with both skills-native and MCP agents

**Deliverables:**
- Updated `railway-doctor/SKILL.md`
- Updated `railway-doctor/check.sh`
- Updated `railway-doctor/fix.sh`

---

### bd-railway-integration.2: skill-creator Railway Template (P0)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 2-3 hours
**Dependencies:** None

**Description:**
Add Railway integration skill template to skill-creator resources, enabling future Railway-specific skills.

**Tasks:**
- [ ] Create `skill-creator/resources/examples/railway-integration-skill.md`
- [ ] Add "Platform Integration Skill" type classification
- [ ] Add GraphQL pattern documentation
- [ ] Update skill-creator workflow with Railway step
- [ ] Add Railway skills to SKILL.md examples
- [ ] Test template by creating sample Railway skill

**Definition of Done:**
- Railway template follows agentskills.io spec
- GraphQL patterns documented and working
- Template tested on Claude Code and Gemini CLI
- Documentation includes both skills-native and MCP patterns

**Deliverables:**
- `skill-creator/resources/examples/railway-integration-skill.md`
- Updated `skill-creator/SKILL.md`
- Example skill created from template

---

### bd-railway-integration.3: devops-dx GraphQL Integration (P1)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 3-4 hours
**Dependencies:** bd-railway-integration.1 (railway-doctor)

**Description:**
Add GraphQL-based environment validation to devops-dx for comprehensive Railway env management.

**Tasks:**
- [ ] Add `Bash(curl:*)` to allowed-tools
- [ ] Create `scripts/validate_railway_env.sh`
- [ ] Implement GraphQL environment config query
- [ ] Add bulk environment validation
- [ ] Add required variable detection
- [ ] Add template syntax validation
- [ ] Update SKILL.md with GraphQL examples

**Definition of Done:**
- GraphQL queries working for all environment types
- Bulk validation handles multiple services
- Error messages are actionable
- Compatible with Railway's GraphQL API

**Deliverables:**
- `devops-dx/scripts/validate_railway_env.sh`
- Updated `devops-dx/SKILL.md`
- Test results from real Railway projects

---

### bd-railway-integration.4: vm-bootstrap Railway Validation (P1)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 1-2 hours
**Dependencies:** None

**Description:**
Add Railway CLI version check and authentication validation to vm-bootstrap.

**Tasks:**
- [ ] Implement `check_railway_cli_version()` function
- [ ] Implement `check_railway_auth()` function
- [ ] Add to required tools verification
- [ ] Update SKILL.md with Railway checks
- [ ] Test on fresh VM bootstrap

**Definition of Done:**
- Railway CLI version validated (>=3.0.0)
- Railway authentication checked
- Clear error messages for setup guidance
- Works in all modes (check, install, strict)

**Deliverables:**
- Updated `vm-bootstrap/verify.sh`
- Updated `vm-bootstrap/SKILL.md`

---

### bd-railway-integration.5: verify-pipeline Railway Stage (P2)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 1-2 hours
**Dependencies:** bd-railway-integration.1 (railway-doctor)

**Description:**
Add Railway deployment verification stage to verify-pipeline skill.

**Tasks:**
- [ ] Add `verify-railway` target to project Makefiles
- [ ] Update verify-pipeline SKILL.md with Railway stage
- [ ] Document Railway verification in workflow
- [ ] Test on affordabot and prime-radiant-ai

**Definition of Done:**
- `make verify-railway` runs railway-doctor checks
- Pipeline verification includes Railway stage
- Documentation updated
- CI integration working

**Deliverables:**
- Updated `verify-pipeline/SKILL.md`
- Makefile snippet for `verify-railway` target

---

### bd-railway-integration.6: multi-agent-dispatch Railway Target (P2)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 2-3 hours
**Dependencies:** bd-railway-integration.1 (railway-doctor)

**Description:**
Add Railway as a virtual dispatch target in multi-agent-dispatch.

**Tasks:**
- [ ] Create `scripts/dispatch/railway.sh`
- [ ] Implement `dispatch_to_railway()` function
- [ ] Add pre-flight check integration
- [ ] Add post-deploy health check
- [ ] Update SKILL.md with Railway examples
- [ ] Test Railway dispatch workflow

**Definition of Done:**
- `dx-dispatch railway "task"` works end-to-end
- Pre-flight checks run before deploy
- Slack notifications work (if configured)
- Error handling is robust

**Deliverables:**
- `multi-agent-dispatch/scripts/dispatch/railway.sh`
- Updated `multi-agent-dispatch/SKILL.md`

---

### bd-railway-integration.7: feature-lifecycle Railway Integration (P3)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 1 hour
**Dependencies:** bd-railway-integration.1 (railway-doctor)

**Description:**
Add optional Railway deployment check to feature-lifecycle finish-feature.

**Tasks:**
- [ ] Detect Railway deployment features
- [ ] Add railway-doctor check prompt
- [ ] Update finish-feature workflow
- [ ] Test on Railway-related feature

**Definition of Done:**
- Railway features detected automatically
- railway-doctor check offered before PR
- Workflow remains optional (not forced)
- Documentation updated

**Deliverables:**
- Updated `feature-lifecycle/finish.sh`
- Updated `feature-lifecycle/SKILL.md`

---

### bd-railway-integration.8: Documentation and Testing (P1)

**Status:** Pending
**Assignee:** claude-code
**Estimated:** 3-4 hours
**Dependencies:** All child tasks

**Description:**
Create comprehensive documentation and test Railway integration across all agent types.

**Tasks:**
- [ ] Create `RAILWAY_AGENT_COMPATIBILITY.md` ✅ (Done)
- [ ] Create `RAILWAY_INTEGRATION_GUIDE.md` ✅ (Done)
- [ ] Create `lib/railway-api.sh` in skills plane
- [ ] Create `lib/railway-common.sh` in skills plane
- [ ] Test on Claude Code (skills-native)
- [ ] Test on Gemini CLI (MCP-dependent)
- [ ] Create test suite for railway-doctor
- [ ] Update AGENTS.md with Railway section
- [ ] Update CLAUDE.md with Railway workflow

**Definition of Done:**
- All documentation complete and reviewed
- Skills plane lib scripts working
- Tests passing on both agent types
- AGENTS.md and CLAUDE.md updated

**Deliverables:**
- `docs/RAILWAY_AGENT_COMPATIBILITY.md` ✅
- `docs/RAILWAY_INTEGRATION_GUIDE.md` ✅
- `lib/railway-api.sh`
- `lib/railway-common.sh`
- Test suite and results

---

## Technical Specifications

### agentskills.io Format Compliance

All Railway-integrated skills MUST follow:

```yaml
---
name: skill-name
description: What this skill does and when to use it
allowed-tools:
  - Bash(railway:*)
  - Bash(curl:*)
  - Read
tags: [railway, deployment, infrastructure]
---

# Skill Name

Purpose and workflow...
```

### GraphQL API Pattern

Standard pattern for Railway GraphQL queries:

```bash
# Environment variable fallback for agent compatibility
SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.agent/skills}"
LIB_SCRIPT="$SKILLS_ROOT/lib/railway-api.sh"

# Always use heredoc for shell safety
bash <<'SCRIPT'
${LIB_SCRIPT} \
  'query envConfig($envId: String!) {
    environment(id: $envId) { id config }
  }' \
  '{"envId": "ENV_ID"}'
SCRIPT
```

### Skills Plane Library Structure

```
~/.agent/skills/lib/
├── railway-api.sh      # GraphQL API wrapper
└── railway-common.sh   # Shared utilities
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Railway API changes | Medium | Medium | Version pinning, fallback to CLI |
| Agent compatibility issues | Low | High | Test on both skill types, document workarounds |
| Breaking changes to agentskills.io | Low | Medium | Follow spec, use validation tools |
| Skills plane mount issues | Low | Medium | Auto-setup scripts, clear error messages |

---

## Rollout Plan

### Phase 1: Core Enhancements (Week 1)
- bd-railway-integration.1: railway-doctor enhancements
- bd-railway-integration.2: skill-creator Railway template
- bd-railway-integration.4: vm-bootstrap Railway validation

### Phase 2: Integration (Week 2)
- bd-railway-integration.3: devops-dx GraphQL integration
- bd-railway-integration.8: Documentation and testing

### Phase 3: Workflow (Week 3)
- bd-railway-integration.5: verify-pipeline Railway stage
- bd-railway-integration.6: multi-agent-dispatch Railway target
- bd-railway-integration.7: feature-lifecycle Railway integration

### Phase 4: Validation (Week 4)
- Cross-agent testing
- Documentation review
- Success metrics validation

---

## Success Criteria

Epic is complete when:

1. ✅ All 7 affected skills updated with Railway patterns
2. ✅ Documentation covers both skills-native and MCP agents
3. ✅ Railway deployment failures <5% of toil commits
4. ✅ avg. time to fix deploy issues <30 min
5. ✅ Skills plane lib scripts working on all agent types
6. ✅ Test suite passing on Claude Code and Gemini CLI
7. ✅ AGENTS.md and CLAUDE.md updated with Railway workflows

---

## Related Epics

- **bd-railway-integration** (this epic)
- **bd-v3-dx** - V3 DX philosophy implementation
- **bd-skills-plane** - Skills plane architecture (bd-3871)
- **bd-agent-mail** - Agent Mail coordination

---

## References

- [Agent Skills Specification](https://agentskills.io/specification)
- [Railway Official Skills](https://github.com/railwayapp/railway-skills)
- [Railway Changelog #0272](https://railway.com/changelog/2026-01-09-railway-agent-skill)
- [SKILLS_PLANE.md](../SKILLS_PLANE.md) - Skills architecture
- [DX_BOOTSTRAP_CONTRACT.md](../DX_BOOTSTRAP_CONTRACT.md) - Session start requirements

---

## Version History

- **v1.0.0** (2025-01-12): Initial epic creation
  - 8 child tasks defined
  - Technical specifications
  - Rollout plan
  - Success criteria
