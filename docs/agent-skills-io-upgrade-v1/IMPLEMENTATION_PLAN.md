# agentskills.io Migration Plan

## agent-skills-io-upgrade-v1

**Date**: 2026-01-10  
**Status**: Planning  
**Epic**: agent-skills-asio

---

## Executive Summary

Migrate `~/agent-skills` to the open agentskills.io standard format. This enables native skill discovery in Claude Code, OpenCode, and Codex CLI while maintaining compatibility with Antigravity and Gemini CLI via the universal-skills MCP bridge.

---

## Architecture

```
                    ┌─────────────────────────────────┐
                    │   ~/agent-skills (GitHub)       │
                    │   agentskills.io format         │
                    └─────────────┬───────────────────┘
                                  │
                    git clone (dx-hydrate.sh)
                                  │
    ┌─────────────────────────────┼─────────────────────────────┐
    │                             │                             │
    ▼                             ▼                             ▼
┌───────────┐             ┌───────────┐             ┌───────────────┐
│  epyc6    │             │  macmini  │             │homedesktop-wsl│
└─────┬─────┘             └─────┬─────┘             └───────┬───────┘
      │                         │                           │
      ▼                         ▼                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Agent Skill Discovery                           │
├─────────────────────────────────────────────────────────────────────┤
│ Claude Code    │ Native agentskills.io         │ No MCP needed     │
│ OpenCode       │ Native agentskills.io         │ No MCP needed     │
│ Codex CLI      │ Native agentskills.io         │ No MCP needed     │
├─────────────────────────────────────────────────────────────────────┤
│ Antigravity    │ universal-skills MCP          │ Bridge required   │
│ Gemini CLI     │ universal-skills MCP          │ Bridge required   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Beads Epic Setup

### Create Epic
```bash
cd ~/agent-skills
bd create --type epic --title "Migrate to agentskills.io Open Standard" \
  --description "Migrate all skills to agentskills.io format, test across VMs and agents, decommission MCP for native agents"
```

### Subtasks
| ID | Title | Type | Status |
|----|-------|------|--------|
| asio.1 | Add frontmatter to all SKILL.md files | task | pending |
| asio.2 | Create migration validation script | task | pending |
| asio.3 | Update dx-hydrate.sh with symlinks | task | pending |
| asio.4 | Configure universal-skills MCP for non-native agents | task | pending |
| asio.5 | Test on epyc6 | task | pending |
| asio.6 | Test on macmini | task | pending |
| asio.7 | Test on homedesktop-wsl | task | pending |
| asio.8 | Decommission MCP for Claude/OpenCode/Codex | task | pending |
| asio.9 | Update AGENTS.md with skills discovery | task | pending |
| asio.10 | Ensure GEMINI.md/CLAUDE.md symlinks | task | pending |

---

## Phase 2: Format Migration

### Current Format
```markdown
# Skill Name

Instructions here...
```

### Target Format (agentskills.io)
```yaml
---
name: skill-name
description: What this skill does and when to use it.
compatibility: Optional requirements
---

# Skill Name

Instructions here...
```

### Migration Script
```bash
#!/bin/bash
# migrate_to_agentskills_io.sh

for dir in ~/agent-skills/*/; do
  skill_file="$dir/SKILL.md"
  if [[ -f "$skill_file" ]]; then
    skill_name=$(basename "$dir")
    # Add frontmatter if missing
    if ! head -1 "$skill_file" | grep -q "^---"; then
      echo "Migrating: $skill_name"
      # Extract first line as description
      desc=$(head -5 "$skill_file" | grep -v "^#" | head -1 | tr -d '\n')
      temp_file=$(mktemp)
      cat > "$temp_file" << EOF
---
name: $skill_name
description: $desc
---

EOF
      cat "$skill_file" >> "$temp_file"
      mv "$temp_file" "$skill_file"
    fi
  fi
done
```

---

## Phase 3: Symlink Setup

### AGENTS.md as Authoritative Source
```bash
cd ~/agent-skills
rm -f GEMINI.md CLAUDE.md
ln -s AGENTS.md GEMINI.md
ln -s AGENTS.md CLAUDE.md
```

### Update AGENTS.md Skills Section
```markdown
## Available Skills

Skills are stored in `~/agent-skills/*/SKILL.md` (agentskills.io format).

**Discovery by Agent:**
- Claude Code: Native `/skill` command
- OpenCode: Native `skill` tool  
- Codex CLI: Native skill loading
- Antigravity/Gemini: Via universal-skills MCP
```

---

## Phase 4: Multi-VM Testing

### Test Matrix
| VM | Agent | Test Command | Expected |
|----|-------|--------------|----------|
| epyc6 | Claude Code | `/skill multi-agent-dispatch` | Skill loads |
| epyc6 | OpenCode | `skill multi-agent-dispatch` | Skill loads |
| epyc6 | Antigravity | MCP: `load_skill` | Skill loads |
| macmini | Claude Code | `/skill beads-workflow` | Skill loads |
| macmini | Codex CLI | Skill invocation | Skill loads |
| homedesktop-wsl | All agents | Full test suite | All pass |

### Verification Script
```python
#!/usr/bin/env python3
# test_skills_across_agents.py

import subprocess
import json

VMS = ["epyc6", "macmini", "homedesktop"]
SKILLS = ["multi-agent-dispatch", "beads-workflow", "sync-feature-branch"]

def test_skill_exists(vm: str, skill: str) -> bool:
    """Check SKILL.md exists and has valid frontmatter."""
    cmd = f"ssh {vm} 'head -5 ~/agent-skills/{skill}/SKILL.md'"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return "---" in result.stdout and "name:" in result.stdout

# Run tests...
```

---

## Phase 5: Decommission MCP for Native Agents

### Current State
All agents use universal-skills MCP.

### Target State
| Agent | MCP Status | Config Change |
|-------|------------|---------------|
| Claude Code | REMOVE | Use native skill discovery |
| OpenCode | REMOVE | Use native skill discovery |
| Codex CLI | REMOVE | Use native skill discovery |
| Antigravity | KEEP | Bridge still needed |
| Gemini CLI | KEEP | Bridge still needed |

### OpenCode Config Update (epyc6, macmini)
```json
{
  "mcp": {
    "slack": { /* keep */ },
    // REMOVE: "skills": { "command": ["npx", "universal-skills", "mcp"] }
  }
}
```

### Keep for Antigravity
Configure in `~/.config/gemini/config.json` or equivalent:
```json
{
  "mcpServers": {
    "skills": {
      "command": ["npx", "universal-skills", "mcp", "--skill-dir", "~/agent-skills"]
    }
  }
}
```

---

## Rollout Plan

| Step | Description | VM | Risk |
|------|-------------|-----|------|
| 1 | Create Beads epic | all | Low |
| 2 | Run migration script | all | Low |
| 3 | Validate frontmatter | all | Low |
| 4 | Create symlinks | all | Low |
| 5 | Test Claude Code | epyc6 | Medium |
| 6 | Test OpenCode | epyc6 | Medium |
| 7 | Remove MCP from native agents | epyc6 | Medium |
| 8 | Repeat 5-7 on macmini | macmini | Low |
| 9 | Repeat 5-7 on homedesktop | homedesktop | Low |
| 10 | Update AGENTS.md | all | Low |
| 11 | Final E2E tests | all | Low |

---

## Rollback Plan

If issues occur:
```bash
# Restore from git
cd ~/agent-skills
git checkout HEAD~1 -- */SKILL.md

# Re-enable MCP for all agents
# Add back skills MCP to opencode.json
```

---

## Success Criteria

- [ ] All SKILL.md files have valid agentskills.io frontmatter
- [ ] GEMINI.md and CLAUDE.md are symlinks to AGENTS.md
- [ ] Claude Code, OpenCode, Codex use native skill discovery
- [ ] Antigravity works via universal-skills MCP
- [ ] All tests pass on epyc6, macmini, homedesktop-wsl
