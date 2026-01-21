# IDE Specifications (V4.2.1)

## Canonical IDE Set

**4 IDEs**: antigravity, claude-code, codex-cli, opencode

**Note**: gemini-cli is **DEPRECATED** as of V4.2.1. Use antigravity instead.

## Supported IDEs

### 1. antigravity
- **agentskills.io**: ✅ Native support
- **Docs**: https://antigravity.google/docs/skills
- **MCP Config**: ~/.gemini/antigravity/mcp_config.json (note: uses gemini config path)
- **Verification**: antigravity mcp list
- **Known Issues**: None

### 2. claude-code
- **agentskills.io**: ✅ Native support
- **Docs**: https://code.claude.com/docs/en/skills
- **MCP Config**: ~/.claude.json
- **Verification**: claude mcp list
- **Known Issues**: None

### 3. codex-cli
- **agentskills.io**: ✅ Native support
- **Docs**: https://developers.openai.com/codex/skills/
- **MCP Config**: ~/.codex/config.toml (TODO - Epic G.6 in V4.2)
- **Verification**: codex mcp list
- **Known Issues**: Slack MCP not configured yet

### 4. opencode
- **agentskills.io**: ✅ Native support
- **Docs**: https://opencode.ai/docs/skills/
- **MCP Config**: ~/.opencode/config.json (TODO - Epic G.7 in V4.2)
- **Verification**: opencode mcp list
- **Known Issues**: Slack MCP not configured yet

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

### epyc6 (Production)
All 4 canonical IDEs installed and configured.

### macmini (Staging)
All 4 canonical IDEs installed and configured.

### homedesktop-wsl (Development)
All 4 canonical IDEs installed and configured.

## agentskills.io Verification

For each IDE, verify agentskills.io support:
```bash
# List available skills
ls ~/.agent/skills

# Test skill loading
<ide> "Use the commit skill"
```

## Migration from gemini-cli

If you were using gemini-cli (deprecated in V4.2.1):
1. Install antigravity: `brew install antigravity`
2. Migrate config: `cp ~/.gemini/settings.json ~/.gemini/antigravity/mcp_config.json`
3. Update MCP configs to use antigravity instead of gemini-cli

## Maintenance

- **Update frequency**: Quarterly or when IDE releases major version
- **Contact**: DX team
- **Last updated**: 2026-01-21 (V4.2.1 - gemini-cli deprecated)

