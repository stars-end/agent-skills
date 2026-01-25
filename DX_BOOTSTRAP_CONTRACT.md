# DX Bootstrap Contract

**Version**: 1.0
**Status**: Canonical Reference
**Applies to**: All repos (prime-radiant-ai, affordabot, llm-common, agent-skills)

This document defines the **mandatory bootstrap sequence** for AI agents working across the Stars-End multi-repo ecosystem.

---

## Overview

The DX Bootstrap Contract ensures:
- ✅ Consistent environment setup across VMs/tools
- ✅ Early detection of environment drift (`dx-check` / `dx-status`)
- ✅ Beads state sync (JSONL + git)
- ✅ Required tools availability (mise/gh/railway/op as applicable)
- ✅ Safety guardrails (DCG)

---

## Session Start Bootstrap (Mandatory Sequence)

**Every agent session MUST execute these steps in order:**

### 1. Git Sync
```bash
cd ~/your-repo
git pull origin master
```

**Purpose**: Ensure working directory matches latest team state
**Failure mode**: If pull fails, resolve conflicts before proceeding

### 2. DX Doctor Check
```bash
# Canonical baseline check (all repos)
dx-check

# Optional: coordinator stack checks (OpenCode + slack-coordinator)
DX_BOOTSTRAP_COORDINATOR=1 dx-doctor
```

**Purpose**: Soft preflight check for:
- Canonical clones on trunk + clean (where required)
- Toolchain presence (mise, gh, railway, op, etc.)
- Optional MCP configuration (slack/z.ai) — warn-only

**Failure mode**:
- ❌ Missing REQUIRED items (baseline) → fix before proceeding
- ⚠️ Missing OPTIONAL items → note but continue

---

## Environment Rules

### Required Environment Variables

**DX_AGENT_ID** (recommended for consistent identity):
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export DX_AGENT_ID="$(hostname -s)-claude-code"
```

**Format**: `<canonical-host>-<platform>` (e.g., `epyc6-claude-code`)
**Status**: P2, warn-only. Provides stable identity for git trailers and coordination logs.
**Fallback**: Auto-detects from hostname + platform if not set.

See `DX_AGENT_ID.md` for full specification.

**Railway** (for prime-radiant-ai, affordabot):
```bash
# Load via railway shell OR export manually
export SUPABASE_URL="..."
export SUPABASE_SERVICE_ROLE_KEY="..."
export GLM_API_KEY="..."
# ... etc (repo-specific)
```

### MCP Servers (Optional)

MCP is optional in the current stack. If used:
- Slack MCP can be helpful for coordinated ops
- z.ai search MCP can be helpful for web search

### Required CLI Tools

**REQUIRED** (all repos):
- `git`: Version control
- `gh`: GitHub CLI (for PR operations)

**RECOMMENDED**:
- `railway`: Environment management (prime-radiant-ai, affordabot)
- `make`: Task automation (prime-radiant-ai, affordabot)

---

## Beads Integration

### Beads State Sync

**Before starting work**:
```bash
bd sync --dry-run  # Check for remote changes
bd sync            # Pull latest JSONL from remote
```

**Failure mode**: Merge conflicts in `.beads/*.jsonl`
- Use `beads-guard` skill for conflict prevention
- Resolve manually if conflicts occur

### Feature-Key Trailers

**All commits MUST include**:
```
Feature-Key: {beads-id}
Agent: {routing-name or program}
Role: {engineer-type}
```

**Examples**:
- `Feature-Key: bd-3871.5`
- `Agent: epyc6-codex-cli` (recommended: `DX_AGENT_ID`)
- `Role: backend-engineer`

---

## Agent-Skills Integration

### Skill Discovery

**All repos should have**:
- `~/.agent/skills/` directory (installed skills)
- Repo-specific skill profile (e.g., `~/.agent/skills/skill-profiles/prime-radiant-ai.json`)

**Check skill health**:
```bash
~/.agent/skills/skills-doctor/check.sh
```

### Auto-Activation

Skills activate via:
- **Semantic matching**: Natural language triggers skill descriptions
- **Explicit invocation**: User says skill name or uses slash command
- **Frontmatter auto-activation**: Skills with `auto-activate: session-start`

---

## Failure Modes & Recovery

### dx-doctor Failures

**Scenario**: Missing railway CLI
**Recovery**: Install via `brew install railway` or npm

### Beads Sync Failures

**Scenario**: JSONL merge conflict
**Recovery**: Use `beads-guard` skill OR manually resolve in `.beads/*.jsonl`

---

## Platform-Specific Integration

### Claude Code

**SessionStart hook** (`.claude/hooks/SessionStart/dx-bootstrap.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Git sync
git pull origin master || echo "⚠️  git pull failed (resolve conflicts)"

# 2. DX doctor
dx-check || true

# 3. Optional coordinator stack checks
DX_BOOTSTRAP_COORDINATOR=1 dx-doctor || true

echo "✅ DX bootstrap complete"
```

### Codex CLI

**Config** (`~/.codex/config.toml`):
```toml
[session]
on_start = "bash ~/.agent/skills/session-start-hooks/dx-bootstrap.sh"
```

### Antigravity

**Config** (`~/.antigravity/config.yaml`):
```yaml
session:
  on_start:
    - git pull origin master
    - dx-check || true
    - bash -lc '[[ "${DX_BOOTSTRAP_COORDINATOR:-0}" == "1" ]] && dx-doctor || true'
```

---

## Compliance Checklist

**For each repo (prime-radiant-ai, affordabot, llm-common)**:

- [ ] AGENTS.md references this contract
- [ ] AGENTS.md has "Session Start Bootstrap" section
- [ ] dx-check/dx-status available on PATH
- [ ] Beads Feature-Key trailer examples shown
- [ ] Platform-specific integration examples (Claude Code, Codex, Antigravity)

---

## Version History

- **v1.0** (2025-12-12): Initial canonical contract (bd-3871.1)

---

**Maintained by**: coordinator (agent-skills repo)
**Questions**: Open a Beads issue in agent-skills (or post in the canonical Slack coordination channel if enabled)
