# Shared DX Core: llm-common & agent-skills

**Status**: Canonical Reference
**Last Updated**: 2025-12-12
**Part of**: bd-3871.6

This document explains the relationship and shared patterns between `llm-common` (shared library) and `agent-skills` (shared tooling/workflows).

---

## Repository Roles

### llm-common: Shared Code Library

**Purpose**: Python library providing LLM abstractions for Affordabot and Prime Radiant

**What it provides**:
- `LLMClient` abstraction (z.ai, OpenRouter, GLM providers)
- `RetrievalBackend` abstraction (Supabase pgvector)
- Web search with caching
- Type-safe Pydantic models
- Agent implementations (browser agent, etc.)

**Repository type**: Secondary (driven by downstream needs)

**Integration method**: Git submodule in downstream repos
```bash
git submodule add git@github.com:stars-end/llm-common.git packages/llm-common
cd packages/llm-common
git checkout v0.4.2  # Pin to stable release
```

**Testing**: 100% test pass rate required (currently 66/66 tests)

### agent-skills: Shared Tooling & Workflows

**Purpose**: Shared skills, GitHub Actions, and workflows for AI agents

**What it provides**:
- Global skills (beads-workflow, create-pull-request, fix-pr-feedback, etc.)
- GitHub Actions composite actions (auto-merge-beads, etc.)
- Workflow templates (.yml.ref files for copy-on-deploy)
- DX doctor checks (mcp-doctor, dx-doctor, skills-doctor, etc.)
- Session start hooks
- Documentation (DX_BOOTSTRAP_CONTRACT.md, this file)

**Repository type**: Shared tooling (symlinked to `~/.agent/skills`)

**Integration method**: Git clone + symlink
```bash
git clone https://github.com/stars-end/agent-skills ~/.agent/skills
```

---

## Shared Patterns

### 1. AGENTS.md / CLAUDE.md Convention

**Both repos follow**:
- Primary file: `AGENTS.md` (canonical agent guidelines)
- Symlink: `CLAUDE.md -> AGENTS.md` (for Claude Code compatibility)
- Session Start Bootstrap section (references DX_BOOTSTRAP_CONTRACT.md)
- Feature-Key trailer examples
- Platform-specific integration notes

**llm-common specifics**:
- Multi-repo context section (primary vs secondary repos)
- No `.claude/` or `.beads/` directories (work tracked in primary repos)
- Git submodule usage instructions

**agent-skills specifics**:
- Skill activation patterns
- CONTRIBUTING.md with agent update instructions
- Skill frontmatter requirements

### 2. Feature-Key Trailers

**Both repos require** commit trailers:
```
Feature-Key: {beads-id}
Agent: {routing-name or program}
Role: {engineer-type}
```

**llm-common special case**:
- Uses Feature-Key from **primary repo** (Affordabot or Prime Radiant)
- Example: `Feature-Key: bd-3871` (from prime-radiant-ai)
- **NOT**: `llm-common-123` (llm-common has no Beads database)

**agent-skills**:
- Uses standard Beads Feature-Keys (tracked in prime-radiant-ai)
- Example: `Feature-Key: bd-3871.5`

### 3. DX Bootstrap Integration

**Both repos reference** the canonical bootstrap contract:
- Link to `DX_BOOTSTRAP_CONTRACT.md` in agent-skills
- Session start sequence documented in AGENTS.md
- dx-doctor checks applicable (but different implementations)

**llm-common bootstrap**:
```bash
cd ~/llm-common
git pull origin master
dx-check || true
# Optional (only if using coordinator services):
# DX_BOOTSTRAP_COORDINATOR=1 dx-doctor || true
# No Beads sync (uses primary repo's Beads)
```

**agent-skills bootstrap**:
```bash
cd ~/.agent/skills
git pull
~/.agent/skills/skills-doctor/check.sh
# No Beads (agent-skills tracked in primary repos)
```

### 4. Testing Philosophy

**llm-common**:
- **Strict**: 100% test pass rate required
- **Comprehensive**: 66/66 tests passing
- **Type-safe**: Full mypy coverage
- **CI gated**: Tests run on every PR

**agent-skills**:
- **Pragmatic**: Skills tested via usage in real workflows
- **Documentation-driven**: Clear examples and edge cases in SKILL.md
- **Integration testing**: Verify skills work across repos/platforms
- **No unit tests**: Skills are shell scripts + markdown (tested in practice)

### 5. Version Strategy

**llm-common**:
- **Semantic versioning**: MAJOR.MINOR.PATCH
- **Git tags**: `v0.4.2`, `v0.5.0`, etc.
- **Stable releases**: Downstream repos pin to specific versions
- **Breaking changes**: Major version bump required

**agent-skills**:
- **Git main branch**: Always latest (no versioning)
- **Agent pulls**: `cd ~/.agent/skills && git pull`
- **Update notifications**: AGENT_UPDATE_INSTRUCTIONS.md
- **Rollout tracking**: Manual checklist per VM

---

## Dependency Flow

```
┌─────────────────────────────────────┐
│  Primary Repos (drive development)  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │   prime-radiant-ai            │  │
│  │   - Beads tracking            │  │
│  │   - Feature-Keys              │  │
│  │   - .claude/, .beads/         │  │
│  └───────────────────────────────┘  │
│                                     │
│  ┌───────────────────────────────┐  │
│  │   affordabot                  │  │
│  │   - Beads tracking            │  │
│  │   - Feature-Keys              │  │
│  │   - .claude/, .beads/         │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
              ▼           ▼
    ┌─────────────┐  ┌──────────────┐
    │ llm-common  │  │ agent-skills │
    │ (submodule) │  │ (symlink)    │
    └─────────────┘  └──────────────┘
       Shared Code    Shared Tooling
```

**Flow**:
1. Work tracked in **primary repos** (Beads, Feature-Keys)
2. llm-common changes driven by **downstream needs** (Affordabot/Prime Radiant)
3. agent-skills changes driven by **cross-repo patterns** (applies to all)
4. Both repos reference each other:
   - llm-common AGENTS.md → agent-skills DX_BOOTSTRAP_CONTRACT.md
   - agent-skills skills → may use llm-common code (future)

---

## Integration Checklist

**When adding to a new repo**:

### llm-common Integration
- [ ] Add as git submodule: `git submodule add git@github.com:stars-end/llm-common.git packages/llm-common`
- [ ] Pin to stable release: `cd packages/llm-common && git checkout v0.4.2`
- [ ] Install dependencies: `cd packages/llm-common && poetry install`
- [ ] Run tests to verify: `poetry run pytest -v`
- [ ] Import in your code: `from llm_common import LLMClient, RetrievalBackend`

### agent-skills Integration
- [ ] Clone to ~/.agent/skills: `git clone https://github.com/stars-end/agent-skills ~/.agent/skills`
- [ ] Create skill profile: `~/.agent/skills/skill-profiles/your-repo.json`
- [ ] Run skills-doctor: `~/.agent/skills/skills-doctor/check.sh`
- [ ] Install dx-doctor hook: See `session-start-hooks/README.md`
- [ ] Update AGENTS.md: Add Session Start Bootstrap section

---

## Contribution Guidelines

### llm-common Contributions

**Process**:
1. Create issue in **primary repo** (Affordabot or Prime Radiant)
2. Use Feature-Key from primary repo in commits
3. Create PR in llm-common with reference to primary issue
4. Ensure 100% test pass rate
5. Update version and CHANGELOG
6. Merge and tag release
7. Update submodule reference in downstream repos

**Example commit**:
```
feat: Add GLM provider support

Adds GLM API client with browser agent support.

Feature-Key: bd-3871
Agent: GreenSnow
Role: backend-engineer
```

### agent-skills Contributions

**Process**:
1. Create Beads issue in primary repo (usually prime-radiant-ai)
2. Use Feature-Key from primary repo
3. Create PR in agent-skills
4. Update AGENT_UPDATE_INSTRUCTIONS.md if agents need to take action
5. Merge and distribute to all VMs
6. Track rollout in AGENT_UPDATE_INSTRUCTIONS.md

**Example commit**:
```
feat: Add dx-bootstrap session start hook

Creates SessionStart hook for Claude Code with dx-doctor check.

Feature-Key: bd-3871.4
Agent: GreenSnow
Role: devops-engineer
```

---

## Common Questions

### Q: Why is llm-common a submodule instead of a PyPI package?

**A**: Allows tight coupling during development while maintaining independent versioning. Downstream repos pin to specific commits/tags for stability.

### Q: Why is agent-skills symlinked to ~/.agent/skills?

**A**: Global installation allows skills to work across all repos without duplication. Agents pull latest with `git pull` in ~/.agent/skills.

### Q: Can llm-common code use agent-skills?

**A**: Not directly. llm-common is a library (no agent tooling dependencies). However, agent-skills *skills* may use llm-common code in the future.

### Q: How do I update both in sync?

**A**:
1. Make llm-common changes first
2. Update agent-skills to reference new llm-common features
3. Update downstream repos to pull new submodule version
4. Distribute agent-skills update to all VMs

### Q: What if agent-skills and llm-common have conflicting requirements?

**A**: They shouldn't - they serve different purposes:
- llm-common: Code library (Python dependencies)
- agent-skills: Tooling (shell scripts, markdown, no Python deps)

If conflict arises, refactor to separate concerns.

---

## Related Documentation

- **[DX Bootstrap Contract](./DX_BOOTSTRAP_CONTRACT.md)** - Canonical session start sequence
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** - Agent-skills contribution guide
- **llm-common AGENTS.md** - llm-common agent guidelines
- **llm-common DEVELOPMENT_STATUS.md** - llm-common development philosophy

---

**Maintained by**: Stars-End agent coordination team
**Questions**: Post to Agent Mail thread `dx-alerts` or open issue
