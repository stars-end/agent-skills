# Railway Skills: Agent Compatibility Analysis

**Document Version:** 1.0.0
**Last Updated:** 2025-01-12
**Related:** Railway Integration Epic (bd-railway-integration)

---

## Executive Summary

Railway's official agent skills use the **agentskills.io** open standard, enabling compatibility across all major AI coding agents. However, there are important differences in **capabilities** and **installation methods** between skills-native agents (Claude Code, Codex CLI, OpenCode) and MCP-dependent agents (Gemini CLI, Antigravity).

---

## Part A: Skills-Native Agents

**Agents:** Claude Code, OpenCode, Codex CLI

### Architecture

Skills-native agents have **built-in support** for the agentskills.io format:

```
┌─────────────────────────────────────────────────────────────┐
│                    Skills-Native Agent                       │
│  (Claude Code / Codex CLI / OpenCode)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────┐   │
│  │  Skill      │  │  Frontmatter │  │  Tool            │   │
│  │  Discovery  │→ │  Parser      │→ │  Restrictions    │   │
│  │             │  │              │  │  (allowed-tools) │   │
│  └─────────────┘  └──────────────┘  └──────────────────┘   │
│         ↓                                                        │
│  ┌─────────────┐                                                │
│  │  Skill      │                                                │
│  │  Activation │                                                │
│  │  (Auto)     │                                                │
│  └─────────────┘                                                │
│                                                                 │
└─────────────────────────────────────────────────────────────┘
```

### Capabilities

| Capability | Support | Notes |
|------------|---------|-------|
| **SKILL.md reading** | ✅ Full | Direct filesystem access |
| **Frontmatter parsing** | ✅ Full | name, description, allowed-tools, tags |
| **Auto-activation** | ✅ Full | Natural language triggers |
| **Tool restrictions** | ✅ Full | `allowed-tools` enforced |
| **Progressive disclosure** | ✅ Full | scripts/, references/, assets/ |
| **Plugin system** | ✅ Full | Marketplace support |

### Railway Skills Installation

**Claude Code (via Marketplace):**
```bash
claude plugin marketplace add railwayapp/railway-claude-plugin
claude plugin install railway@railway-claude-plugin
```

**Claude Code (from local clone):**
```bash
git clone git@github.com:railwayapp/railway-claude-plugin.git ~/railway-claude-plugin
claude --plugin-dir ~/railway-claude-plugin/plugins/railway
```

**Other Skills-Native Agents:**
```bash
# Copy skills directory to agent's skills location
cp -r railway-skills/plugins/railway/skills/ ~/.agent/skills/railway/

# Or add to skills plane
cp -r railway-skills/plugins/railway/skills/* ~/agent-skills/
```

### allowed-tools Support

Skills-native agents **fully support** the `allowed-tools` field:

```yaml
---
allowed-tools:
  - Bash(railway:*)
  - Bash(curl:*)
  - Read
  - Write
---
```

**Enforcement:**
- Agent checks tool permissions before execution
- Prompts user for approval if tool not in allowed list
- Can auto-approve via PreToolUse hooks (Railway uses this)

---

## Part B: Universal-Skills/MCP Agents

**Agents:** Gemini CLI, Antigravity, OpenAI Codex

⚠️ **DEPRECATED**: universal-skills MCP server is deprecated (V4.2.1). MCP-dependent agents are no longer supported for Railway skills. Use skills-native agents (Claude Code, OpenCode, Codex CLI) instead.

### Architecture

**NOTE**: The following documentation is preserved for historical reference only. MCP-dependent agent support is deprecated.

MCP-dependent agents previously used the **universal-skills MCP server**:

```
┌─────────────────────────────────────────────────────────────┐
│                   MCP-Dependent Agent                         │
│  (Gemini CLI / Antigravity)                                   │
├─────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌──────────────────────────────────────┐  │
│  │  MCP        │  │  Universal-Skills MCP Server         │  │
│  │  Client     │→ │  (npx universal-skills mcp)           │  │
│  └─────────────┘  └──────────────────────────────────────┘  │
│                           ↓                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Skills Plane: ~/.agent/skills → ~/agent-skills     │  │
│  │  - Scans for SKILL.md files                          │  │
│  │  - Exposes as MCP resources                          │  │
│  │  - Provides load_skill() function                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────┘
```

### Capabilities

| Capability | Support | Notes |
|------------|---------|-------|
| **SKILL.md reading** | ✅ Full | Via MCP resources |
| **Frontmatter parsing** | ✅ Full | Via universal-skills |
| **Auto-activation** | ⚠️ Partial | Via `load_skill()` calls |
| **Tool restrictions** | ❌ Limited | Not enforced by all MCP clients |
| **Progressive disclosure** | ✅ Full | scripts/, references/, assets/ |
| **Plugin system** | ❌ None | Manual skill loading |

### Railway Skills Installation

⚠️ **DEPRECATED**: The following installation method is no longer supported. universal-skills MCP is deprecated (V4.2.1). Use skills-native agents instead.

**[DEPRECATED] Setup universal-skills MCP:**
```bash
# Gemini CLI (DEPRECATED - universal-skills is deprecated)
gemini mcp add --transport stdio skills -- npx universal-skills mcp

# Antigravity (DEPRECATED - universal-skills is deprecated)
antigravity mcp add --transport stdio skills -- npx universal-skills mcp
```

**Add Railway skills to skills plane:**
```bash
# Clone Railway skills
git clone https://github.com/railwayapp/railway-skills.git /tmp/railway-skills

# Copy to skills plane
cp -r /tmp/railway-skills/plugins/railway/skills/* ~/agent-skills/

# Verify mount
ls -la ~/.agent/skills  # Should symlink to ~/agent-skills
```

**Load Railway skill in agent:**
```python
# Within Gemini CLI or Antigravity
skill = load_skill("railway-deploy")
```

### allowed-tools Support

**Status:** ⚠️ **Limited/Partial**

MCP-dependent agents may **not enforce** `allowed-tools` restrictions:

- ✅ `allowed-tools` is **parsed** from frontmatter
- ⚠️ Tool enforcement depends on **MCP client implementation**
- ❌ No universal standard for tool permissions via MCP

**Workaround:** Railway's PreToolUse hooks don't work via MCP. Manual approval may be required.

---

## Comparison Matrix

| Aspect | Skills-Native | MCP-Dependent |
|--------|---------------|---------------|
| **Installation** | Plugin marketplace OR manual copy | Manual copy to skills plane |
| **Discovery** | Built-in skill scanner | universal-skills MCP server (DEPRECATED) |
| **Activation** | Automatic via triggers | `load_skill()` function call (DEPRECATED) |
| **Tool restrictions** | ✅ Enforced | ⚠️ Client-dependent (DEPRECATED) |
| **PreToolUse hooks** | ✅ Supported | ❌ Not via MCP (DEPRECATED) |
| **Updates** | `claude plugin update` | `git pull` in skills plane (DEPRECATED) |
| **Cross-platform** | Per-agent implementation | Universal via MCP (DEPRECATED) |

⚠️ **Note**: MCP-Dependent column is deprecated (V4.2.1). Use skills-native agents only.

---

## Railway Skills Feature Compatibility

### Features by Agent Type

| Feature | Claude Code | Codex CLI | OpenCode | Gemini CLI | Antigravity |
|---------|-------------|-----------|----------|------------|-------------|
| **deploy skill** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **environment skill** | ✅ | ✅ | ✅ | ✅ | ✅ |
| **GraphQL queries** | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| **Auto-approve hooks** | ✅ | ⚠️ | ⚠️ | ❌ | ❌ |
| **Marketplace install** | ✅ | ❌ | ❌ | ❌ | ❌ |

**Legend:**
- ✅ Full support
- ⚠️ Partial support (manual workarounds)
- ❌ Not supported

### GraphQL Pattern Compatibility

Railway's GraphQL pattern uses bash heredocs with a library script:

```bash
bash <<'SCRIPT'
${CLAUDE_PLUGIN_ROOT}/skills/lib/railway-api.sh \
  'query envConfig($envId: String!) {
    environment(id: $envId) { id config }
  }' \
  '{"envId": "ENV_ID"}'
SCRIPT
```

**Skills-Native Agents:** ✅ Full support
- `CLAUDE_PLUGIN_ROOT` is set by the agent
- Script is available in the plugin directory

**MCP-Dependent Agents:** ⚠️ Requires adaptation
- `CLAUDE_PLUGIN_ROOT` is **not set**
- `railway-api.sh` must be in **skills plane lib/** instead

**MCP-Compatible Pattern:**
```bash
# For MCP agents, use skills plane lib
bash <<'SCRIPT'
${HOME}/.agent/skills/lib/railway-api.sh \
  'query envConfig($envId: String!) {
    environment(id: $envId) { id config }
  }' \
  '{"envId": "ENV_ID"}'
SCRIPT
```

---

## Recommendations

### For agent-skills Repository

1. **Railway library script** should be in shared location:
   ```
   ~/.agent/skills/lib/railway-api.sh
   ```
   This works for **both** skill-native and MCP agents.

2. **Environment variable abstraction:**
   ```bash
   # Use fallback for CLAUDE_PLUGIN_ROOT
   SKILLS_ROOT="${CLAUDE_PLUGIN_ROOT:-$HOME/.agent/skills}"
   LIB_SCRIPT="$SKILLS_ROOT/lib/railway-api.sh"
   ```

3. **allowed-tools is recommended but not required:**
   - Include it for skills-native agents
   - Document that MCP agents may not enforce it

### For Railway Skills Adoption

**Skills-Native Agents (Recommended):**
- Use Claude Code marketplace for easiest installation
- Full feature support including auto-approve hooks
- Automatic updates via `claude plugin update`

**MCP-Dependent Agents (Workarounds):**
- Manual installation to skills plane
- Copy `lib/railway-api.sh` to `~/.agent/skills/lib/`
- Use environment variable fallback pattern
- Manual approval for GraphQL API calls

### Hybrid Approach

**Recommended for agent-skills repo:**

Create a **Railway Integration** skill that:
1. Works with both agent types
2. Detects agent type (skills-native vs MCP)
3. Adjusts paths and patterns accordingly
4. Provides fallbacks for missing features

---

## Sources

- [Agent Skills Specification](https://agentskills.io/specification)
- [Railway Skills Repository](https://github.com/railwayapp/railway-skills)
- [Universal-Skills MCP](https://github.com/intellectronica/gemini-cli-skillz)
- [Gemini CLI Skills Documentation](https://geminicli.com/docs/cli/skills/)
- [SKILLS_PLANE.md](../SKILLS_PLANE.md) - Skills plane architecture

---

## Version History

- **v1.0.0** (2025-01-12): Initial analysis
  - Skills-native vs MCP-dependent agent comparison
  - Railway skills compatibility matrix
  - GraphQL pattern adaptations
