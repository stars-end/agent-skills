---
name: cass-memory
description: Local-first procedural/episodic memory workflow with opt-in sanitized cross-agent digest sharing.
---

# CASS Memory (Fleet Sync V2.1)

Use this skill when recurring patterns, decisions, and and failure playbooks should persist across sessions.

## Status
- Fleet contract: CLI-native tool, not a required IDE MCP-rendered server
- Canonical install: `brew install dicklesworthstone/tap/cm`
- Canonical health checks:
  - `cm --version`
  - `cm quickstart --json`
  - `cm doctor --json`

## Upstream Docs
- GitHub: `https://github.com/Dicklesworthstone/cass_memory_system`
- README install + usage: `https://github.com/Dicklesworthstone/cass_memory_system#installation`
- README agent workflow: `https://github.com/Dicklesworthstone/cass_memory_system#for-ai-agents-the-most-important-section`
- README MCP server notes: `https://github.com/Dicklesworthstone/cass_memory_system#mcp-server`

## Contract
- Session logs remain local by default.
- Cross-agent sharing is opt-in only and must use sanitized summaries.
- Never persist raw secrets, raw transcripts, or tokens.
- Primary workflow is CLI-first:
  - `cm context "<task>" --json`
  - `cm quickstart --json`
  - `cm doctor --json`
- `cm serve` is optional HTTP MCP, not a required Fleet Sync IDE surface.

## Controls
- Enable sharing: `CASS_SHARE_MEMORY=1`
- Disable sharing: `CASS_NO_SHARE=1`

## Fleet Usage
- Treat `cass-memory` as a host capability across canonical VMs.
- Do not fail IDE MCP drift checks because `cm` is absent from a client config.
- If `cm doctor --json` is degraded or unhealthy, treat that as runtime health debt, not MCP config blocker
