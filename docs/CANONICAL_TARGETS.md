# Canonical Targets Registry

This document defines the single source of truth for canonical VMs, IDEs, and configuration paths in the agent-skills project.

## Canonical VM Hosts

| Host | OS | Description | SSH Target |
|------|-----|-------------|------------|
| homedesktop-wsl | Linux (WSL2) | Primary Linux dev environment | `fengning@homedesktop-wsl` |
| macmini | macOS | macOS Dev machine | `fengning@macmini` |
| epyc6 | Linux | VPS (local) | `fengning@v2202509262171386004` |

### Environment Variables

- `CANONICAL_VM_LINUX` = `fengning@homedesktop-wsl`
- `CANONICAL_VM_MACOS` = `fengning@macmini`

## Canonical IDE Set

The following IDEs are officially supported for MCP and tooling integration:

| IDE | Description |
|-----|-------------|
| antigravity | Gemini-based AI IDE |
| claude-code | Anthropic's official Claude Code CLI |
| codex-cli | Codex CLI tool |
| opencode | OpenCode AI Server |

### Per-IDE Config Paths

#### Linux (including WSL2)

| IDE | Config Path |
|-----|-------------|
| antigravity | `~/.gemini/antigravity/mcp_config.json` |
| claude-code | `~/.claude/settings.json` |
| codex-cli | `~/.codex/config.toml` |
| opencode | `~/.opencode/config.json` |

#### macOS

| IDE | Config Path |
|-----|-------------|
| antigravity | `~/.gemini/antigravity/mcp_config.json` |
| claude-code | `~/.claude/settings.json` |
| codex-cli | `~/.codex/config.toml` |
| opencode | `~/.opencode/config.json` |

## Usage

### Shell Script

Source the canonical targets script in your shell:

```bash
source ~/agent-skills/scripts/canonical-targets.sh

# List all VMs
list_canonical_vms

# Get config path for an IDE
get_ide_config "claude-code" "linux"

# Detect current OS
detect_os
```

### Programmatic Access

The shell script can be sourced by other scripts to access the canonical targets.

```bash
#!/bin/bash
source ~/agent-skills/scripts/canonical-targets.sh

# Iterate over canonical IDEs
for ide in "${CANONICAL_IDES[@]}"; do
  config=$(get_ide_config "$ide" "$(detect_os)")
  echo "$ide: $config"
done
```

## Maintenance

When adding new VMs or IDEs:

1. Update this documentation file
2. Update `scripts/canonical-targets.sh`
3. Ensure all doctor scripts reference this registry

## Related Files

- `scripts/canonical-targets.sh` - Shell script with environment variables
- `scripts/mcp-doctor/check.sh` - MCP doctor (should reference this registry)
- `scripts/ssh-key-doctor/check.sh` - SSH key doctor (should reference this registry)
