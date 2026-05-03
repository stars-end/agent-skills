---
name: cass-memory
description: Pilot-only CLI episodic memory workflow for explicit cross-agent memory experiments.
tags:
  - memory
  - cli
  - fleet-sync
  - episodic
  - local-first
---

# CASS Memory (Pilot Only)

CLI-native episodic memory for explicit experiments in recurring-pattern capture. This is not part of the canonical default assistant loop.

## Tool Class

**`integration_mode: cli`**

CASS Memory is a CLI-native tool. It is NOT rendered to IDE MCP configs. It runs as a standalone binary.

## Status

- Default stack status: NOT CANONICAL
- Fleet status: pilot-only / disabled by default in the manifest
- Use only when the task explicitly asks for cross-session or cross-agent memory experimentation
- Do not require this tool in standard repo workflows
- Active pilot contract: `docs/specs/2026-04-03-cass-memory-cross-vm-dx-pilot.md` (`bd-953g`)
- Active pilot starter package: `docs/runbook/cass-memory-pilot-quickstart.md` (`bd-9q92`)
- Candidate contract: `docs/specs/2026-04-03-cass-memory-candidate-contract.md` (`bd-h3f1`)
- Retrieval + cross-VM path: `docs/specs/2026-04-03-cass-memory-context-retrieval-and-cross-vm-path.md` (`bd-dk79`)
- Seeded operator heuristics: `docs/runbook/cass-memory-seeded-heuristics.md`
- Pilot templates:
  - `templates/cass-memory-pilot-entry-template.md`
  - `templates/cass-memory-pilot-reuse-log-template.csv`

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

# Repair degraded local setup
cm doctor --fix --no-interactive
```

## Usage Patterns

### Local Memory (Default)
Session logs remain local by default.

```bash
# Get task-specific context before non-trivial DX work
cm context "repair MCP daemon EOF issue" --json

# Inspect the actual context payload
cm context "prefer z.ai coding endpoints first for this coding lane" --json | jq '.data.relevantBullets'

# Store a memory/playbook bullet
cm playbook add "Always use worktrees for canonical repos" --category workflow

# Inspect rules
cm playbook list

# Broader similarity search when context is too narrow
cm similar "worktree recovery" --threshold 0.1 --json
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
5. **Primary agent read path**: use `cm context "<task>" --json` before trying broader retrieval
6. **Candidate-first writes**: agent judgment can nominate candidates, but durable shared memory requires promotion
7. **Task-shaped retrieval**: phrase reads like an actual operator task; use `cm similar` for loose wording checks
8. **Cross-VM split**: upstream `remoteCass` is for SSH-based remote history, while promoted-rule sharing should use explicit playbook export/import

## Controls

| Env Var | Purpose |
|---------|---------|
| `CASS_SHARE_MEMORY` | Enable cross-agent digest sharing |
| `CASS_NO_SHARE` | Disable all sharing |

For the current upstream CLI, explicit privacy controls are also available via:

```bash
cm privacy status
cm privacy enable
cm privacy disable
```

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

### Layer 1 (Host Runtime)
```bash
cm --version && cm quickstart --json && cm doctor --json
```

### Layer 4 (Client Visibility)
- NOT REQUIRED - CLI tools don't appear in `codex mcp list` or similar

## Related

- `fleet-sync`: Fleet Sync orchestrator
- `serena`: MCP symbol-aware edits + memory
