# Canonical Targets Registry

This document defines the single source of truth for canonical VMs, IDEs, and configuration paths in the agent-skills project.

## Canonical VM Hosts

| Host | OS | Description | SSH Target |
|------|-----|-------------|------------|
| homedesktop-wsl | Linux (WSL2) | Primary Linux dev environment | `fengning@homedesktop-wsl` |
| macmini | macOS | macOS Dev machine | `fengning@macmini` |
| epyc6 | Linux | Primary Linux dev host (this machine) | `feng@epyc6` |

**IMPORTANT: SSH Username Variations**
- SSH targets use **username@host** format because usernames vary across machines
- epyc6 uses `feng@` while WSL/macOS use `fengning@`
- **Always use full `username@host` syntax** when SSH'ing between VMs
- Bare hostnames (e.g., `ssh homedesktop-wsl`) rely on SSH config which may not be configured on all machines
- Example: `ssh fengning@homedesktop-wsl "ru --version"` (CORRECT)
- Example: `ssh homedesktop-wsl "ru --version"` (MAY FAIL if SSH config missing)

## Canonical Git Trunk

**Trunk branch**: `master`

**Rule**: keep the canonical clones in `~/<repo>` on `master` and clean (no uncommitted changes). If you need to work on a feature branch, use a worktree (recommended) or a separate `*.wip.*` directory, so automation can still fast-forward the canonical clones.

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

## Canonical Repos

These repos are expected to exist as canonical clones at:

- `~/agent-skills`
- `~/prime-radiant-ai`
- `~/affordabot`
- `~/llm-common`

They should remain on `master` for cross-VM sync and DX verification.

## Repo Sync with ru (repo_updater)

**ru** is the canonical tool for keeping repositories synchronized across VMs.

### Manual Sync (Recommended)

```bash
# Sync all configured repos
ru sync

# Check status without modifying
ru status

# Sync specific repo only
ru sync stars-end/agent-skills
```

### Automated Sync (Optional)

**Note: ru is manual-only by design.** For automated updates, use platform-specific scheduling:

**Linux (cron):**
```bash
# Run every hour
# crontab -e
0 * * * * /usr/local/bin/ru sync --non-interactive --quiet
```

**macOS (launchd):**
```xml
<!-- ~/Library/LaunchAgents/ru.sync.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ru.sync</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/ru</string>
        <string>sync</string>
        <string>--non-interactive</string>
        <string>--quiet</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
</dict>
</plist>
```

### ru vs bd sync

| Tool | Purpose | Scope |
|------|---------|-------|
| `ru sync` | Git repo synchronization across VMs | All repos in ru config |
| `bd sync` | Beads issue database persistence | `.beads/issues.jsonl` export/import |

Both serve different purposes and should be used together.

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
- `ssh-key-doctor/check.sh` - SSH key doctor (should reference this registry)
