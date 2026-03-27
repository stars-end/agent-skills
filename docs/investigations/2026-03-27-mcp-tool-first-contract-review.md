# Investigation: MCP Tool-First Contract Review (bd-b8te)
Date: 2026-03-27
Agent: Gemini CLI
Status: DRAFT

## 1. Current Stack Map & Roles

| Tool | Role | Integration | Coverage Status |
|------|------|-------------|-----------------|
| context-plus | Semantic Discovery / Mapping | MCP | Core (High value for Research) |
| llm-tldr | Static Analysis / Token Minimization | MCP | Core (High value for Deep Dive) |
| serena | Assistant Memory / Symbol Editing | MCP | Core (High value for Persistence) |
| cass-memory | Cross-Agent Episodic Memory | CLI | Redundant (Disconnected from MCP) |
| Beads | Workflow / Task State | CLI/Dolt | Foundational (Non-negotiable) |

### Redundancy Analysis
The episodic memory need is already effectively met by a combination of serena (turn-by-turn continuity), Beads (persistent task state), and Git (durable change history). cass-memory adds a layer of CLI-native complexity that is rarely utilized by MCP-first agents.

## 2. Behavioral Failure Root Cause
Agents (including myself) primarily rely on native grep_search and read_file because:
1. **Instruction Segregation**: MCP tools are listed in Extended Workflows in AGENTS.md, signifying optional status.
2. **Lifecycle Ambiguity**: The Development Lifecycle mandated in system prompts and docs does not explicitly require context-plus or llm-tldr as prerequisites for read_file.
3. **Repo-Level Omission**: Major repositories like prime-radiant-ai lack any mention of these tools in their AGENTS.md context.

## 3. CASS/CM Decision
**Recommendation: REMOVE FROM CANONICAL DEFAULT.**
cass-memory should be demoted to an opt-in pilot for specialized cross-VM long-term knowledge tasks. It does not currently justify its footprint in the standard developer tool-belt.

## 4. Enforcement Plan (Mechanistic)

### Phase 1: Global Baseline Update (agent-skills)
- **Target**: scripts/publish-baseline.zsh
- **Change**: Move context-plus, llm-tldr, and serena from Extended to Core Workflows.
- **Action**: Inject a Tool-First Discovery Mandate into the Layer A constraints.

### Phase 2: Repo-Level Injection (prime-radiant-ai)
- **Target**: fragments/universal-baseline.md
- **Change**: Add explicit instruction that context-plus (semantic) or llm-tldr (structural) MUST be used before large-scale read_file operations.

### Phase 3: Skill Contract Hardening
- **Target**: core/issue-first/SKILL.md
- **Change**: Add Research Verification requirement that references MCP discovery tools.

## 5. Recommended Next Task Ordering

1. **bd-b8te** (Current): Finalize this review and open draft PR.
2. **bd-2n6g**: Implement publish-baseline.zsh re-categorization.
3. **bd-2qhi**: Update universal-baseline.md with tool-first mandates.
4. **bd-dqhl**: Formally deprecate cass-memory and remove from mcp-tools.yaml.
