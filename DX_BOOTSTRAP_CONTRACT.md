# DX Bootstrap Contract

**Version**: 1.0
**Status**: Canonical Reference
**Applies to**: All repos (prime-radiant-ai, affordabot, llm-common, agent-skills)

This document defines the **mandatory bootstrap sequence** for AI agents working across the Stars-End multi-repo ecosystem.

---

## Overview

The DX Bootstrap Contract ensures:
- ✅ Consistent environment setup across VMs/tools
- ✅ Early detection of environment drift (dx-doctor)
- ✅ Proper Agent Mail coordination (multi-agent workflows)
- ✅ Beads state sync (JSONL + git)
- ✅ Required tools availability

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
# Prime Radiant / Affordabot
make dx-doctor

# llm-common (no Makefile)
~/.agent/skills/dx-doctor/check.sh

# agent-skills (no Makefile)
~/.agent/skills/dx-doctor/check.sh
```

**Purpose**: Soft preflight check for:
- Required MCP servers (agent-mail)
- Optional MCP servers (universal-skills, serena, z.ai)
- CLI tools (railway, gh)

**Failure mode**:
- ❌ Missing REQUIRED items → HARD FAIL (fix before proceeding)
- ⚠️ Missing OPTIONAL items → SOFT WARN (note but continue)

### 3. Agent Mail Registration (If Configured)

**Check if Agent Mail is configured**:
```bash
# Verify env vars
echo $AGENT_MAIL_URL
echo $AGENT_MAIL_BEARER_TOKEN
```

**If configured** (env vars present):

```bash
# Register identity (creates stable routing name)
# Use project-appropriate script or manual registration

python3 - <<'PY'
import json, os, urllib.request

url = os.environ["AGENT_MAIL_URL"]
token = os.environ["AGENT_MAIL_BEARER_TOKEN"]
project_key = os.path.abspath(".")  # Current repo root
alias = f"{os.uname().nodename}-{program}"  # e.g., "epyc6-claude-code"

def tool(name, arguments, id):
    req = urllib.request.Request(
        url,
        data=json.dumps({"jsonrpc":"2.0","id":id,"method":"tools/call","params":{"name":name,"arguments":arguments}}).encode(),
        headers={"Content-Type":"application/json","Authorization":"Bearer "+token},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload = json.loads(resp.read().decode())["result"]
    if payload.get("isError"):
        raise RuntimeError(payload["content"][0]["text"])
    return json.loads(payload["content"][0]["text"])

tool("ensure_project", {"human_key": project_key}, 1)
agent = tool("create_agent_identity", {
    "project_key": project_key,
    "program": os.uname().nodename,
    "model": program,  # "claude-code", "codex-cli", "antigravity", etc.
    "task_description": f"alias={alias}"
}, 2)

print(f"✅ Registered as: {agent['name']}")
PY
```

**If NOT configured**:
- Note in session summary: "Agent Mail not configured (Beads + git only)"
- Proceed without coordination features

### 4. Check Inbox (If Agent Mail Registered)

```bash
# Via MCP tool (if available in your environment)
# Check for urgent messages, task assignments, DX alerts
```

**Purpose**: See if coordinator has assigned work or posted DX alerts

---

## Environment Rules

### Required Environment Variables

**DX_AGENT_ID** (recommended for consistent identity):
```bash
# Add to ~/.bashrc, ~/.zshrc, or ~/.profile
export DX_AGENT_ID="$(hostname -s)-claude-code"
```

**Format**: `<magicdns-host>-<platform>` (e.g., `v2202509262171386004-claude-code`)
**Status**: P2, warn-only. Provides stable identity for git trailers and Agent Mail.
**Fallback**: Auto-detects from hostname + platform if not set.

See `DX_AGENT_ID.md` for full specification.

**Agent Mail** (if using multi-agent coordination):
```bash
export AGENT_MAIL_URL="http://macmini:8765/mcp/"
export AGENT_MAIL_BEARER_TOKEN="<provided-by-coordinator>"
```

**Railway** (for prime-radiant-ai, affordabot):
```bash
# Load via railway shell OR export manually
export SUPABASE_URL="..."
export SUPABASE_SERVICE_ROLE_KEY="..."
export GLM_API_KEY="..."
# ... etc (repo-specific)
```

### Required MCP Servers

**REQUIRED** (all repos):
- `agent-mail`: Multi-agent coordination, DX alerts, file leases

**OPTIONAL** (recommended):
- `serena`: Advanced code search/edit
- `z.ai search`: Web search capabilities

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
- `Agent: GreenSnow` (if Agent Mail registered) OR `Agent: claude-code` (if not)
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

**Scenario**: Missing agent-mail MCP
**Recovery**: Install agent-mail MCP using platform-specific instructions (see `mcp-doctor/SKILL.md`)

**Scenario**: Missing railway CLI
**Recovery**: Install via `brew install railway` or npm

### Agent Mail Failures

**Scenario**: Registration fails (401 Unauthorized)
**Recovery**: Verify `AGENT_MAIL_BEARER_TOKEN` is correct, check with coordinator

**Scenario**: Project not found
**Recovery**: Run `ensure_project` with correct absolute path

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
if [[ -f Makefile ]] && grep -q "dx-doctor" Makefile; then
    make dx-doctor
else
    ~/.agent/skills/dx-doctor/check.sh || true
fi

# 3. Agent Mail (if configured)
if [[ -n "${AGENT_MAIL_URL:-}" ]]; then
    echo "✅ Agent Mail configured"
    # Registration handled by skill or manual process
fi

echo "✅ DX bootstrap complete"
```

### Codex CLI

**Config** (`~/.codex/config.toml`):
```toml
[session]
on_start = "~/.agent/skills/dx-doctor/check.sh"
```

### Antigravity

**Config** (`~/.antigravity/config.yaml`):
```yaml
session:
  on_start:
    - git pull origin master
    - make dx-doctor || ~/.agent/skills/dx-doctor/check.sh
```

---

## Compliance Checklist

**For each repo (prime-radiant-ai, affordabot, llm-common)**:

- [ ] AGENTS.md references this contract
- [ ] AGENTS.md has "Session Start Bootstrap" section
- [ ] dx-doctor available (Makefile target OR direct script)
- [ ] Agent Mail env vars documented (if applicable)
- [ ] Beads Feature-Key trailer examples shown
- [ ] Platform-specific integration examples (Claude Code, Codex, Antigravity)

---

## Version History

- **v1.0** (2025-12-12): Initial canonical contract (bd-3871.1)

---

**Maintained by**: coordinator (agent-skills repo)
**Questions**: Post to Agent Mail thread `dx-alerts` or open issue in agent-skills
