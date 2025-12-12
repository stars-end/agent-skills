# mcp-doctor

## Description

Soft doctor to verify the **canonical MCP servers** are discoverable/configured on the current VM/tooling.

This does **not** validate the MCP servers themselves beyond basic “config present” checks, and it must **never print secrets**
(bearer tokens, API keys, headers).

## Canonical MCP servers (stars-end)

These are the MCP integrations we consider “standard” across our fleet:

1. **universal-skills** — https://github.com/klaudworks/universal-skills  
2. **Serena MCP** — https://github.com/oraios/serena/blob/main/README.md  
3. **Z.ai search MCP** — https://docs.z.ai/devpack/mcp/search-mcp-server  
4. **Agent Mail MCP** — https://github.com/Dicklesworthstone/mcp_agent_mail  

## What it checks

- Searches common MCP config locations for the server names/URLs above:
  - Repo-local: `.claude/settings.json`, `.vscode/mcp.json`, `codex.mcp.json`, `gemini.mcp.json`, `.mcp.json`, `opencode.json`
  - User/global: `~/.claude/settings.json`, `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`
- Reports `configured` / `missing` per MCP server name.
- Optionally reports presence of CLI tools we rely on:
  - `railway`, `gh`

## Usage

```bash
~/.agent/skills/mcp-doctor/check.sh
```

Optional:

```bash
export MCP_DOCTOR_STRICT=1  # exit non-zero if any required MCP missing
~/.agent/skills/mcp-doctor/check.sh
```

