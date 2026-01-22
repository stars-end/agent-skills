# DX_AGENT_ID Standard (bd-n1rv)

## Overview

`DX_AGENT_ID` is a **warn-only** identity standard for agents working across multiple repos, VMs, and platforms.

**Goal**: Consistent agent identification in git trailers, logs, and multi-agent coordination (Agent Mail, Beads).

**Status**: P2, non-blocking. Agents should set it, but missing DX_AGENT_ID only triggers warnings, not failures.

## Format

```
DX_AGENT_ID=<magicdns-host>-<platform>
```

**Examples:**
- `epyc6-claude-code` (Linux, Claude Code)
- `macmini-codex-cli` (macOS, Codex CLI)
- `epyc6-antigravity` (Linux VM, Antigravity)

**Components:**
- `<magicdns-host>`: Short hostname (from `hostname -s` or Tailscale/MagicDNS name)
- `<platform>`: Tool/agent platform (`claude-code`, `codex-cli`, `antigravity`, etc.)

## Usage

### 1. Set DX_AGENT_ID (Recommended)

**In your shell profile** (`~/.bashrc`, `~/.zshrc`, or `~/.profile`):

```bash
export DX_AGENT_ID="epyc6-claude-code"
```

**Or per-session** (temporary):

```bash
export DX_AGENT_ID="$(hostname -s)-claude-code"
```

### 2. Use the Helper Script

The helper script `scripts/get_agent_identity.sh` implements the fallback logic:

```bash
~/.agent/skills/scripts/get_agent_identity.sh
```

**Fallback order:**
1. `$DX_AGENT_ID` (if set and non-empty) ← **Highest priority**
2. `$AGENT_NAME` (legacy, if set and non-empty)
3. Auto-detect: `$(hostname -s)-<platform>`

**Example integration:**

```bash
# In git commit trailers
AGENT_ID="$(~/.agent/skills/scripts/get_agent_identity.sh)"
git commit -m "fix: Bug description

Feature-Key: bd-xyz
Agent: $AGENT_ID
Role: backend-engineer"
```

## Why DX_AGENT_ID?

**Multi-repo coordination**: When working across multiple repos (e.g., prime-radiant-ai, affordabot, llm-common), agents need a stable identity that works regardless of current working directory.

**Agent Mail integration**: Agent Mail uses agent names for message routing. DX_AGENT_ID provides a consistent name across all repos/sessions.

**Beads tracking**: Git trailers use `Agent:` field to track which agent made commits. DX_AGENT_ID ensures consistency.

**Platform diversity**: Teams use Claude Code, Codex CLI, Antigravity, etc. DX_AGENT_ID captures both host and platform for full context.

## Migration Path

**Current state**: Agents use various methods (hostname, AGENT_NAME, manual strings).

**Migration steps:**

1. **Phase 1 (current)**: Warn-only. Scripts log warnings if DX_AGENT_ID is missing but continue.
2. **Phase 2 (future)**: CI jobs may require DX_AGENT_ID for strict validation.
3. **Phase 3 (optional)**: Automated setup during VM bootstrap.

## Skills Integration

**Updated skills that recommend DX_AGENT_ID:**

- `vm-bootstrap`: Suggests setting DX_AGENT_ID during environment setup
- `mcp-doctor`: Optionally checks for DX_AGENT_ID (future enhancement)
- `beads-workflow`: Uses DX_AGENT_ID in git trailers if set

**Example from `vm-bootstrap`:**

```bash
# During VM setup
if [[ -z "${DX_AGENT_ID:-}" ]]; then
  echo "⚠️  DX_AGENT_ID not set. Recommended:"
  echo "   export DX_AGENT_ID=\"$(hostname -s)-claude-code\""
  echo "   Add to ~/.bashrc or ~/.profile"
fi
```

## Technical Details

### Auto-Detection Logic

When DX_AGENT_ID is not set, the helper script auto-detects platform:

```bash
get_platform() {
  if [[ -n "${CLAUDE_CODE:-}" ]]; then
    echo "claude-code"
  elif [[ -n "${CODEX_CLI:-}" ]]; then
    echo "codex-cli"
  elif [[ -n "${ANTIGRAVITY:-}" ]]; then
    echo "antigravity"
  elif command -v claude >/dev/null 2>&1; then
    echo "claude-code"
  elif command -v codex >/dev/null 2>&1; then
    echo "codex-cli"
  else
    echo "unknown"
  fi
}
```

### Legacy AGENT_NAME Support

The `AGENT_NAME` environment variable is still supported as a fallback for backward compatibility. Existing scripts using `AGENT_NAME` will continue to work.

**Recommendation**: Migrate to `DX_AGENT_ID` for consistency with the new standard.

## Security Notes

- DX_AGENT_ID contains **no secrets** (only hostname + platform)
- Safe to log, include in git commits, and share across agents
- Never include tokens, API keys, or credentials in DX_AGENT_ID

## Examples by Platform

### Claude Code (Linux)

```bash
# In ~/.bashrc
export DX_AGENT_ID="epyc6-claude-code"
```

### Codex CLI (macOS)

```bash
# In ~/.zshrc
export DX_AGENT_ID="$(hostname -s)-codex-cli"
```

### Antigravity (Linux)

```bash
# In ~/.profile
export DX_AGENT_ID="epyc6-antigravity"
```

## Related Documents

- `SKILLS_PLANE.md`: Shared skills architecture
- `vm-bootstrap/SKILL.md`: VM setup and toolchain verification
- `mcp-doctor/SKILL.md`: MCP server health checks

## Future Enhancements

**Phase 2 (future)**:
- Add DX_AGENT_ID check to `vm-bootstrap` install mode
- Optionally validate format (hostname-platform)
- Integrate with Agent Mail for automatic identity registration

**Phase 3 (CI)**:
- Require DX_AGENT_ID in GitHub Actions workflows
- Strict mode for CI environments (fail if missing)
