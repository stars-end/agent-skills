# IDE Specifications (V4.2.1)

## Canonical IDE Set

**5 IDEs**: antigravity, claude-code, codex-cli, opencode, gemini-cli

gemini-cli is canonical from this release and is under staged enforcement:
- Week 1: missing gemini lane is **YELLOW**.
- Week 2+: missing gemini lane is **RED** in governance checks.

## DX Global Constraints Rail (All IDEs)

All IDE agents must see the same “hard constraints” (no canonical writes, worktree-first, done gate).

Single source:
- `~/agent-skills/dist/dx-global-constraints.md`

Recommended install (per VM / per user):
```bash
~/agent-skills/scripts/dx-ide-global-constraints-install.sh --apply
```

Verification:
```bash
~/agent-skills/scripts/dx-ide-global-constraints-install.sh --check
```

Installed targets:
- codex-cli: `~/.codex/AGENTS.md`
- claude-code: `~/.claude/CLAUDE.md`
- opencode: `~/.config/opencode/AGENTS.md`
- gemini-cli: `~/.gemini/GEMINI.md`

## Supported IDEs

### 1. antigravity
- **agentskills.io**: ✅ Native support
- **Docs**: https://antigravity.google/docs/skills
- **MCP Config**: `~/.gemini/antigravity/mcp_config.json` (uses gemini config path)
- **Verification**: `antigravity mcp list`
- **Slack MCP**: Supported via `~/agent-skills/scripts/setup-slack-mcp.sh antigravity`
- **Known Issues**: None

### 2. claude-code
- **agentskills.io**: ✅ Native support
- **Docs**: https://code.claude.com/docs/en/skills
- **MCP Config**: `~/.claude.json`
- **Verification**: `claude mcp list`
- **Slack MCP**: Supported via `~/agent-skills/scripts/setup-slack-mcp.sh claude-code`
- **Known Issues**: None

### 3. codex-cli
- **agentskills.io**: ✅ Native support
- **Docs**: https://developers.openai.com/codex/skills/
- **MCP Config**: `~/.codex/config.toml`
- **Verification**: `codex mcp list`
- **Slack MCP**: Supported via `~/agent-skills/scripts/setup-slack-mcp.sh codex-cli`
- **Known Issues**: None (Slack MCP configuration now supported)

**Skills install note**: Codex discovers skills via the `.agents/skills` convention (repo + user scopes).
To expose `~/agent-skills/*/*/SKILL.md` to Codex (user scope), run:
```bash
~/agent-skills/scripts/dx-agents-skills-install.sh --apply
```

### 4. opencode
- **agentskills.io**: ✅ Native support
- **Docs**: https://opencode.ai/docs/skills/
- **MCP Config**: `~/.opencode/config.json`
- **Verification**: `opencode mcp list`
- **Slack MCP**: Supported via `~/agent-skills/scripts/setup-slack-mcp.sh opencode`
- **Known Issues**: None (Slack MCP configuration now supported)

### 5. gemini-cli
- **agentskills.io**: ✅ Native support
- **Docs**: https://github.com/google-gemini/gemini-cli
- **Constraints Rail**: `~/.gemini/GEMINI.md`
- **Binary**: `~/.gemini/gemini`
- **Canonical profile path**: `~/.gemini/antigravity/mcp_config.json`
- **Verification**: `gemini --version` and `test -f ~/.gemini/GEMINI.md`
- **Slack MCP**: not yet auto-discovered by helper tooling; governed via Fleet checks

## Installation Instructions

### antigravity
```bash
brew install antigravity
antigravity auth login
```

### claude-code
```bash
npm install -g @anthropic/claude-code
claude auth login
```

### codex-cli
```bash
brew install codex-cli
codex auth login
```

### opencode
```bash
brew install opencode
opencode auth login
```

## VM-Specific Configuration

The following VMs are defined in `scripts/canonical-targets.sh`:

### epyc6 (Production)
- Location: `feng@epyc6` (primary Linux dev host)
- Expected: All 5 canonical IDEs installed and configured
- Verification: Run `dx-status` to check

### macmini (Staging)
- Location: `fengning@macmini`
- Expected: All 5 canonical IDEs installed and configured
- Note: Uses native 1Password app (not systemd LoadCredentialEncrypted)

### homedesktop-wsl (Development)
- Location: `fengning@homedesktop-wsl`
- Expected: All 5 canonical IDEs installed and configured
- Verified: ✅ All services passing as of 2026-01-22

## agentskills.io Verification

For each IDE, verify agentskills.io support:
```bash
# List available skills
ls ~/.agent/skills

# Test skill loading
<ide> "Use the commit skill"
```

## Migration from gemini-cli

If gemini-cli is not yet present:
1. Install binary: `brew install gemini-cli`
2. Add `~/.gemini/GEMINI.md`
3. Ensure canonical profile artifact `~/.gemini/antigravity/mcp_config.json` is valid
4. Governance uses staged enforcement (7-day warn window, then fail-on-missing)

## Slack MCP Configuration

To configure Slack MCP for all canonical IDEs:
```bash
# Configure all IDEs
~/agent-skills/scripts/setup-slack-mcp.sh --all

# Configure specific IDE
~/agent-skills/scripts/setup-slack-mcp.sh claude-code
```

See `~/agent-skills/scripts/setup-slack-mcp.sh` for verification commands per IDE.

## Maintenance

- **Update frequency**: Quarterly or when IDE releases major version
- **Contact**: DX team
- **Last updated**: 2026-03-04 (V8.4 hardening - gemini canonicalized)
- **Canonical targets**: `~/agent-skills/scripts/canonical-targets.sh`
- **See also**: `~/agent-skills/docs/CANONICAL_TARGETS.md`
