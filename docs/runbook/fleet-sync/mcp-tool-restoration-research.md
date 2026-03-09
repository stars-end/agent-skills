# Fleet Sync MCP Tool Restoration Research (bd-d8f4)

## Overview
Authoritative research bundle for `llm-tldr`, `context-plus`, `cass-memory`, and `serena`.

## Per-Tool Contract Table

| Tool | Upstream | Contract Type | Status |
|------|----------|---------------|--------|
| `llm-tldr` | `parcadei/llm-tldr` | `mcp` | [VERIFIED] |
| `context-plus` | `ForLoopCodes/contextplus` | `mcp` | [RECOMMENDED] |
| `cass-memory` | `Dicklesworthstone/cass_memory_system` | `cli` | [VERIFIED] |
| `serena` | `oraios/serena` | `mcp` | [PARTIALLY VERIFIED] |

## Live-Docs Map & Primary-Source URLs

- **llm-tldr:** https://github.com/parcadei/llm-tldr#readme
- **context-plus:** https://github.com/ForLoopCodes/contextplus
- **cass-memory:** https://github.com/Dicklesworthstone/cass_memory_system
- **serena:** https://github.com/oraios/serena

## Tool 1: llm-tldr
- **Status:** [VERIFIED]
- **Upstream Docs:** https://github.com/parcadei/llm-tldr#readme
- **Install Docs:** https://github.com/parcadei/llm-tldr
- **Contract:** `mcp`
- **Host Install:** `uv tool install "llm-tldr==1.5.2"`
- **Host Health:** `tldr-mcp --version`
- **Usage (Agent Workflow):** MCP client handles `tldr-mcp` execution. Transport uses `stdio`.

## Tool 2: context-plus
- **Status:** [RECOMMENDED]
- **Upstream Docs:** https://github.com/ForLoopCodes/contextplus
- **Install Docs:** https://www.npmjs.com/package/contextplus
- **Contract:** `mcp`
- **Host Install:** `npm install -g contextplus@1.0.7`
- **Host Health:** `contextplus --version`
- **Usage (Agent Workflow):** Fleet Sync manages it as an MCP server; client uses stdio transport.

## Tool 3: cass-memory
- **Status:** [VERIFIED]
- **Upstream Docs:** https://github.com/Dicklesworthstone/cass_memory_system
- **Install Docs:** https://github.com/Dicklesworthstone/cass_memory_system#installation
- **Contract:** `cli` (CLI-native)
- **Host Install:** `curl -fsSL "https://raw.githubusercontent.com/Dicklesworthstone/cass_memory_system/main/install.sh" | bash -s -- --easy-mode --verify`
- **Host Health:** `cm --version`
- **Usage (Agent Workflow):** Run `cm trauma scan --days 30`, `cm guard --status`, etc. directly in agent shell.

## Tool 4: serena
- **Status:** [PARTIALLY VERIFIED] (Executable proof found locally, client visibility pending)
- **Upstream Docs:** https://oraios.github.io/serena/
- **Install Docs:** https://github.com/oraios/serena#quick-start
- **Contract:** `mcp`
- **Host Install:** `uv tool install git+https://github.com/oraios/serena.git`
- **Host Health:** `serena start-mcp-server --help`
- **Usage (Agent Workflow):** Configured as an MCP server via `serena start-mcp-server` (transport uses `stdio`).

## Blockers
- **Cross-VM Client Visibility Verification Pending.** While host install and binary execution are confirmed for `serena` and others, Layer 4 client visibility (e.g., `claude mcp list`) is not yet comprehensively verified across all intended surfaces. Full verification requires evidence collection before declaring "no blockers."