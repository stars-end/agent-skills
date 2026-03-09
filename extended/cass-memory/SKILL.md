---
name: cass-memory
description: CLI-native procedural/episodic memory workflow with opt-in sanitized cross-agent digest sharing.
tags:
  - memory
  - cli
  - fleet-sync
  - episodic
  - local-first
---

# CASS Memory (Fleet Sync V2.2)

CLI-native episodic memory for recurring patterns, decisions, and failure playbooks.

## Tool Class

**`integration_mode: cli`**

CASS Memory is a CLI-native tool, NOT rendered to IDE MCP configs. It runs as a standalone binary.

## Installation

```bash
# Install from GitHub (npm)
npm install -g Dicklesworthstone/cass_memory_system
```

## Health Commands

```bash
# Version check
cm --version

# Quick health check
cm quickstart --json

# Full diagnostics
cm doctor --json
```

## Usage Patterns

### Local Memory (Default)
Session logs remain local by default.

```bash
# Store a memory
cm remember "Pattern: Always use worktrees for canonical repos"

# Recall memories
cm recall "worktree"

# List recent
cm list --recent
```

### Cross-Agent Sharing (Opt-In)
Cross-agent sharing uses sanitized summaries only.

```bash
# Enable sharing
export CASS_SHARE_MEMORY=1

# Disable sharing
export CASS_NO_SHARE=1
```

## Contract

1. **Local-first**: Session logs remain local by default
2. **Opt-in sharing**: Cross-agent sharing must be explicitly enabled
3. **Sanitized output**: Never persist raw secrets, raw transcripts, or tokens
4. **No IDE config**: CLI-native, not rendered to IDE MCP configs

## Controls

| Env Var | Purpose |
|---------|---------|
| `CASS_SHARE_MEMORY` | Enable cross-agent digest sharing |
| `CASS_NO_SHARE` | Disable all sharing |

## Expected Output

- Local playbook updates
- Optional redacted digest records for fleet learning
- Decision logs for recurring patterns

## Fleet Sync Integration

CASS Memory is managed by Fleet Sync as a CLI tool:

```bash
# Check health via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --check --json | jq '.tools[] | select(.tool=="cass-memory")'

# Install via Fleet Sync
~/agent-skills/scripts/dx-mcp-tools-sync.sh --apply --json
```

## Upstream

- **Repo**: https://github.com/Dicklesworthstone/cass_memory_system
- **Docs**: https://github.com/Dicklesworthstone/cass_memory_system#readme

## Validation

Layer 1 (Host Runtime):
```bash
cm --version && cm quickstart --json && cm doctor --json
```

Layer 4 (Client Visibility):
- NOT REQUIRED - CLI tools don't appear in `codex mcp list` or similar

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `llm-tldr`: MCP static analysis
- `context-plus`: MCP structural context
