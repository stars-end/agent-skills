# Railway Integration Guide

**Document Version:** 1.0.0
**Last Updated:** 2025-01-12
**Related:** Railway Integration Epic (bd-railway-integration)

---

## Overview

This guide covers integrating Railway's official agent skills with the agent-skills registry. Railway provides comprehensive deployment and management capabilities via the agentskills.io standard format.

**Key Concept:** Two-layer approach
1. **Pre-flight (railway-doctor)** - Validate before deploy
2. **Operations (Railway official skills)** - Deploy and manage

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Railway Deployment Workflow                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────┐     ┌──────────────────┐                 │
│  │ railway-doctor   │     │  Railway         │                 │
│  │ check.sh         │────→│  Official        │                 │
│  │ (Pre-flight)     │     │  Skills          │                 │
│  └──────────────────┘     └──────────────────┘                 │
│         │                           │                            │
│         │ passes                    │                            │
│         │                           │                            │
│         │                    ┌──────┴──────┐                    │
│         │                    │             │                    │
│         │              ┌─────▼─────┐ ┌────▼─────┐              │
│         │              │ railway   │ │ railway  │              │
│         │              │ deploy    │ │environment│              │
│         │              └─────┬─────┘ └────┬─────┘              │
│         │                    │            │                    │
│         └────────────────────┴────────────┴────────────────────┘
│                              │                                 │
│                         ┌────▼─────┐                          │
│                         │ railway  │                          │
│                         │deployment│                          │
│                         │ (monitor)│                          │
│                         └──────────┘                          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Installation

### Step 1: Skills Plane Setup (Required)

```bash
# Verify skills plane
ls -la ~/.agent/skills

# Should show symlink to ~/agent-skills
# ~/.agent/skills -> ~/agent-skills

# If not present:
~/agent-skills/scripts/ensure_agent_skills_mount.sh
```

### Step 2: Install Railway Official Skills

**For Claude Code (Recommended):**
```bash
claude plugin marketplace add railwayapp/railway-claude-plugin
claude plugin install railway@railway-claude-plugin
```

**For Other Agents:**
```bash
# Clone Railway skills
git clone https://github.com/railwayapp/railway-skills.git /tmp/railway-skills

# Copy Railway lib scripts to skills plane
mkdir -p ~/.agent/skills/lib
cp /tmp/railway-skills/plugins/railway/skills/lib/*.sh ~/.agent/skills/lib/

# Verify
ls -la ~/.agent/skills/lib/
# Should show: railway-api.sh, railway-common.sh
```

### Step 3: Verify Setup

```bash
# Test railway-doctor
~/.agent/skills/railway-doctor/check.sh

# Test Railway library
bash ~/.agent/skills/lib/railway-api.sh \
  'query { currentUser { id } }' \
  '{}'
```

---

## Skills Matrix

| Skill | Purpose | Source | Agent Type |
|-------|---------|--------|------------|
| **railway-doctor** | Pre-flight validation | agent-skills | All |
| **railway deploy** | Push code | Railway official | Skills-native |
| **railway environment** | Manage config | Railway official | Skills-native |
| **railway service** | Manage services | Railway official | Skills-native |
| **railway new** | Create services | Railway official | Skills-native |
| **railway deployment** | Monitor deployments | Railway official | Skills-native |

---

## Workflow Examples

### Example 1: Deploy to Railway

```bash
# 1. Run pre-flight checks
~/.agent/skills/railway-doctor/check.sh

# 2. If checks pass, deploy
railway up --detach

# 3. Monitor deployment
railway logs --build --lines 50
```

### Example 2: Fix Deployment Issues

```bash
# 1. Run pre-flight checks
~/.agent/skills/railway-doctor/check.sh

# 2. Fix issues found
~/.agent/skills/railway-doctor/fix.sh

# 3. Re-check
~/.agent/skills/railway-doctor/check.sh

# 4. Deploy
railway up --ci  # Stream build logs
```

### Example 3: Manage Environment Variables

```bash
# Using GraphQL (more powerful than CLI)
bash <<'SCRIPT'
~/.agent/skills/lib/railway-api.sh \
  'query envConfig($envId: String!) {
    environment(id: $envId) {
      id
      config(decryptVariables: false)
    }
  }' \
  '{"envId": "YOUR_ENV_ID"}'
SCRIPT
```

---

## GraphQL API Pattern

Railway's official skills use GraphQL for reliable operations:

```bash
# Always use heredoc for shell safety
bash <<'SCRIPT'
~/.agent/skills/lib/railway-api.sh \
  'query envConfig($envId: String!) {
    environment(id: $envId) { id config }
  }' \
  '{"envId": "ENV_ID"}'
SCRIPT
```

**Benefits:**
- More reliable than CLI parsing
- Better error handling
- Can query across multiple services
- Works for complex mutations

**Common Queries:**

| Query | Purpose |
|-------|---------|
| `environment(id)` | Get full config |
| `project(id)` | List services |
| `currentUser` | Verify auth |
| `environmentStagedChanges` | Check pending changes |

---

## Pre-Flight Validation Stages

railway-doctor performs multi-stage validation:

| Stage | Checks | Fail Action |
|-------|--------|-------------|
| **Pre-build** | Lockfiles, imports | Block deploy |
| **Build** | Config, Railpack version | Block deploy |
| **Pre-deploy** | Env vars, monorepo config | Block deploy |
| **Post-deploy** | Health, smoke tests | Rollback prompt |

**Common Issues Detected:**

| Issue | Symptom | Fix |
|-------|---------|-----|
| Lockfile out of sync | Build fails | `railway-doctor fix` |
| Import errors | Runtime 500 | Fix import paths |
| Monorepo root dir | Missing packages | Use custom commands |
| Build/start conflict | Invalid config | Edit railway.toml |
| Missing env vars | 500 errors | Set via dashboard |

---

## Composability

### railway-doctor → Railway Official Skills

```
railway-doctor check
         │
         │ passes
         ▼
┌─────────────────────────────────────┐
│  Choose next action:                 │
│                                     │
│  • railway deploy → Push code        │
│  • railway environment → Fix config  │
│  • railway service → Manage svc     │
│  • railway new → Create service      │
└─────────────────────────────────────┘
```

### Integration Points

| After | Use Skill | For |
|-------|-----------|-----|
| railway-doctor passes | `railway deploy` | Push code |
| Deploy succeeds | `railway deployment` | View logs |
| Config issues found | `railway environment` | Fix settings |
| Need new service | `railway new` | Create service |
| Domain needed | `railway domain` | Add custom domain |

---

## Agent-Specific Notes

### Claude Code (Skills-Native)

```bash
# Install via marketplace
claude plugin marketplace add railwayapp/railway-claude-plugin
claude plugin install railway@railway-claude-plugin

# Skills auto-activate on Railway-related prompts
# Example: "deploy to railway" → railway deploy skill activates
```

**Features:**
- ✅ Auto-activation
- ✅ allowed-tools enforcement
- ✅ PreToolUse hooks (auto-approve GraphQL)
- ✅ Marketplace updates

### Gemini CLI (MCP-Dependent) - DEPRECATED

⚠️ **DEPRECATED (V4.2.1)**: universal-skills MCP is deprecated. Use skills-native agents (Claude Code, OpenCode, Codex CLI) instead.

```bash
# [DEPRECATED] Setup universal-skills MCP
# DO NOT USE - universal-skills is deprecated
gemini mcp add --transport stdio skills -- npx universal-skills mcp

# Railway skills available via load_skill()
load_skill("railway-deploy")
```

**Features:**
- ✅ Skill loading via MCP (DEPRECATED)
- ⚠️ Manual activation required (DEPRECATED)
- ⚠️ Tool restrictions not enforced (DEPRECATED)
- ❌ No auto-approve hooks (DEPRECATED)

### Codex CLI (Skills-Native)

```bash
# Copy skills directory
cp -r railway-skills/plugins/railway/skills/* ~/.agent/skills/

# Skills auto-discover on startup
```

**Features:**
- ✅ Auto-discovery
- ✅ allowed-tools enforcement
- ⚠️ No marketplace (manual install)

---

## Troubleshooting

### "Railway CLI not found"

```bash
# Install via mise
mise use -g railway@latest

# Or via npm
npm install -g @railway/cli

# Verify
railway --version
```

### "railway-api.sh not found"

```bash
# Verify lib directory exists
ls -la ~/.agent/skills/lib/

# If missing, copy from Railway skills
git clone https://github.com/railwayapp/railway-skills.git /tmp/railway-skills
cp /tmp/railway-skills/plugins/railway/skills/lib/*.sh ~/.agent/skills/lib/
```

### "Pre-flight check fails"

```bash
# Run fix script
~/.agent/skills/railway-doctor/fix.sh

# Re-check
~/.agent/skills/railway-doctor/check.sh

# If issue persists, check specific component:
# - Lockfiles: poetry lock, pnpm install
# - Imports: Test imports locally
# - Env vars: Set in Railway dashboard
```

### "GraphQL query fails"

```bash
# Verify Railway authentication
railway status

# Check railway-api.sh syntax
bash -x ~/.agent/skills/lib/railway-api.sh \
  'query { currentUser { id } }' \
  '{}'

# Common issues:
# - Missing Railway token
# - Invalid GraphQL syntax
# - Missing environment ID
```

---

## Best Practices

### DO ✅

1. **Always run railway-doctor before deploying**
   - Catches 80% of deployment failures
   - Saves iteration time

2. **Use GraphQL for complex operations**
   - More reliable than CLI
   - Better error messages

3. **Use --detach for most deploys**
   - Non-blocking
   - Check status later

4. **Use --ci when debugging**
   - Stream build logs
   - Immediate feedback

5. **Set DX_AGENT_ID for tracking**
   - Consistent agent identity
   - Better git attribution

### DON'T ❌

1. **Don't skip pre-flight checks**
   - You'll waste time debugging in Railway

2. **Don't use rootDirectory for shared monorepos**
   - Breaks package imports
   - Use custom commands instead

3. **Don't set identical build/start commands**
   - Invalid configuration
   - Railway will reject

4. **Don't store secrets in repo**
   - Use Railway environment variables
   - Keep .env files out of git

---

## Related Documentation

- [RAILWAY_AGENT_COMPATIBILITY.md](./RAILWAY_AGENT_COMPATIBILITY.md) - Agent-specific compatibility
- [railway-doctor SKILL.md](../railway-doctor/SKILL.md) - Pre-flight validation
- [devops-dx SKILL.md](../devops-dx/SKILL.md) - Environment management
- [SKILLS_PLANE.md](../SKILLS_PLANE.md) - Skills architecture

---

## External Resources

- [Railway Official Skills](https://github.com/railwayapp/railway-skills)
- [Railway Documentation](https://docs.railway.com)
- [Agent Skills Specification](https://agentskills.io/specification)
- [Railway Changelog #0272](https://railway.com/changelog/2026-01-09-railway-agent-skill)

---

## Version History

- **v1.0.0** (2025-01-12): Initial implementation
  - Two-layer architecture (pre-flight + operations)
  - Installation instructions
  - GraphQL patterns
  - Agent-specific notes
  - Troubleshooting guide
