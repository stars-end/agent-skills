# mcp-doctor

## Description

Soft doctor to verify the **canonical MCP servers** are discoverable/configured on the current VM/tooling.

This does **not** validate the MCP servers themselves beyond basic “config present” checks, and it must **never print secrets**
(bearer tokens, API keys, headers).

## Required vs Optional MCP servers

### REQUIRED (skills plane)

1. **universal-skills** — https://github.com/klaudworks/universal-skills
   - **Required** for the shared skills plane
   - Enables skill discovery and management across all agents
   - All agents MUST have this configured

### OPTIONAL (recommended but not required)

2. **Agent Mail MCP** — https://github.com/Dicklesworthstone/mcp_agent_mail
   - Recommended for multi-agent coordination, DX alerts, and shared state
   - Falls back gracefully if missing

3. **Serena MCP** — https://github.com/oraios/serena/blob/main/README.md
   - Recommended for advanced code analysis
   - Optional enhancement

4. **Z.ai search MCP** — https://docs.z.ai/devpack/mcp/search-mcp-server
   - Recommended for web search capabilities
   - Optional enhancement  

## What it checks

- Searches common MCP config locations for the server names/URLs above:
  - Repo-local: `.claude/settings.json`, `.vscode/mcp.json`, `codex.mcp.json`, `gemini.mcp.json`, `.mcp.json`, `opencode.json`
  - User/global: `~/.claude/settings.json`, `~/.claude.json`, `~/.codex/config.toml`, `~/.gemini/settings.json`
- Reports `configured` / `missing` per MCP server name.
- **Verifies the canonical skills mount invariant**:
  - `~/.agent/skills` MUST point to `~/agent-skills` (symlink or exact copy)
  - This ensures universal-skills MCP can discover skills correctly
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

## Platform setup (copy/paste)

This section is intentionally **copy/paste friendly** and avoids embedding secrets.

### Required: Skills mount

**First**, ensure the canonical skills mount is set up:

```bash
# Ensure ~/agent-skills exists
if [[ ! -d ~/agent-skills ]]; then
  git clone https://github.com/stars-end/agent-skills.git ~/agent-skills
fi

# Create symlink ~/.agent/skills -> ~/agent-skills
mkdir -p ~/.agent
ln -sfn ~/agent-skills ~/.agent/skills

# Verify
ls -la ~/.agent/skills
```

You can also use the helper script:

```bash
~/agent-skills/scripts/ensure_agent_skills_mount.sh
```

### A) Claude Code

1) **universal-skills** (stdio)

```bash
claude mcp add --transport stdio skills -- npx universal-skills mcp
```

2) **Z.ai Web Search MCP** (http)

```bash
export ZAI_API_KEY="..."   # set via 1Password/env
claude mcp add -s user -t http web-search-prime \
  https://api.z.ai/api/mcp/web_search_prime/mcp \
  --header "Authorization: Bearer ${ZAI_API_KEY}"
```

3) **Serena MCP**

Follow Serena’s MCP setup and confirm it’s visible in `.claude/settings.json`:
https://github.com/oraios/serena/blob/main/README.md

4) **Agent Mail MCP**

Prefer Agent Mail’s installer/autodetect (it writes Claude config without printing tokens):
https://github.com/Dicklesworthstone/mcp_agent_mail

### B) Codex CLI

Codex stores MCP config in `~/.codex/config.toml`:

- **universal-skills** (stdio)

```bash
codex mcp add skills -- npx universal-skills mcp
```

- **Agent Mail** (streamable http) – use env var for token:

```toml
[mcp_servers.agent-mail]
url = "http://macmini:8765/mcp/"
bearer_token_env_var = "AGENT_MAIL_BEARER_TOKEN"
```

- **Z.ai Web Search** (streamable http) – use env var for API key:

```toml
[mcp_servers.web-search-prime]
url = "https://api.z.ai/api/mcp/web_search_prime/mcp"
env_http_headers = { "Authorization" = "ZAI_API_KEY" }
```

### C) Gemini CLI / Antigravity (shared settings)

Gemini CLI uses `~/.gemini/settings.json` (and supports `gemini mcp add …`).
Antigravity should share the same file.

- **Z.ai Web Search**:

```bash
export ZAI_API_KEY="..."   # set via 1Password/env
gemini mcp add --transport http web-search-prime https://api.z.ai/api/mcp/web_search_prime/mcp \
  --header "Authorization: Bearer ${ZAI_API_KEY}"
```

Or write to `~/.gemini/settings.json` (env var reference):

```json
{
  "mcpServers": {
    "web-search-prime": {
      "httpUrl": "https://api.z.ai/api/mcp/web_search_prime/mcp",
      "headers": { "Authorization": "Bearer $ZAI_API_KEY" }
    }
  }
}
```

### Notes on running checks every session

Default: run `mcp-doctor` as part of `dx-doctor` because it is offline and fast (local file scan + `command -v`).

If you need to quiet it:
- set `DX_SKIP_MCP=1` before running `dx-doctor` (repo-level support).
