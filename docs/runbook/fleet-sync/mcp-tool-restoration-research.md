# Fleet Sync MCP Tool Restoration Research (bd-d8f4)

## Overview
This document captures the current status, installation methods, and validation requirements for the intended Fleet Sync MCP tool stack across all canonical VMs and IDE surfaces.

## Tool Status Summary

| Tool | Status | Current Version | Target Version | Runtime | Recommend |
|------|--------|-----------------|----------------|---------|-----------|
| `llm-tldr` | Working | 1.5.2 | 1.5.2 | Python | Enable |
| `context-plus` | Broken | 0.4.2 (Typo) | 1.0.7 | Node | Enable |
| `cass-memory` | Broken | 1.0.0 (Invalid) | 0.2.3 | Node/Bun | Enable |
| `serena` | Broken | 0.9.1 (Wrong) | 0.9.9 (Git) | Python | Enable |

---

## Tool 1: llm-tldr
- **Status:** Working
- **Real Upstream:** [simonw/llm-tldr](https://github.com/simonw/llm-tldr) (or equivalent)
- **Current Install Method:** `uv tool install "llm-tldr==1.5.2"`
- **Required Runtime:** Python 3.12+
- **Executable/MCP Entrypoint:** `llm-tldr` (Package provides `tldr` and `tldr-mcp` entrypoints)
- **Health Command:** `llm-tldr --version`
- **Config/Env Vars:** None required for baseline.
- **Cross-VM Notes:** Verified on `epyc6` and `macmini`.

## Tool 2: context-plus
- **Status:** Partially Working (Incorrect package name in manifest)
- **Real Upstream:** [ForLoopCodes/contextplus](https://github.com/ForLoopCodes/contextplus)
- **Real Package Name:** `contextplus` (on npm, NOT `@forloopcodes/contextplus`)
- **Current Install Method:** `npm install -g contextplus` or `npx -y contextplus`
- **Required Runtime:** Node.js 20+
- **Executable/MCP Entrypoint:** `contextplus`
- **Health Command:** `contextplus --version`
- **Config/Env Vars:** `OLLAMA_EMBED_MODEL`, `OLLAMA_CHAT_MODEL` (Optional).
- **Cross-VM Notes:** Needs global npm install on all VMs.

## Tool 3: cass-memory
- **Status:** Broken (Wrong package name, version, and binary name)
- **Real Upstream:** [Dicklesworthstone/cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system)
- **Real Package Name:** `cass-memory` (Source: `Dicklesworthstone/cass_memory_system` on GitHub)
- **Current Install Method:** `npm install -g Dicklesworthstone/cass_memory_system`
- **Required Runtime:** Node.js 20+ (Bun recommended but npm works)
- **Executable/MCP Entrypoint:** `cm`
- **Health Command:** `cm --version`
- **Config/Env Vars:** `CASS_SHARE_MEMORY` (Opt-in).
- **Cross-VM Notes:** `bun` is missing on `epyc6`, recommend `npm` for better cross-VM compatibility.

## Tool 4: serena
- **Status:** Broken (Points to AMQP client `serena` on PyPI)
- **Real Upstream:** [oraios/serena](https://github.com/oraios/serena)
- **Real Package Name:** `serena` (But must install from GitHub to avoid PyPI collision)
- **Current Install Method:** `uv tool install git+https://github.com/oraios/serena.git`
- **Required Runtime:** Python 3.12+
- **Executable/MCP Entrypoint:** `serena`
- **Health Command:** `serena start-mcp-server --help`
- **Config/Env Vars:** Uses `.serena/memories/` for state.
- **Cross-VM Notes:** Must avoid `serena` package on PyPI which is an unrelated AMQP client.

---

## Blockers
1. `mcp-tools.yaml` has typos in package names (`@forloopcodes/contextplus` vs `contextplus`).
2. `mcp-tools.yaml` has version mismatches (`1.0.0` for `cass-memory` which doesn't exist on npm).
3. `mcp-tools.yaml` points to the wrong `serena` package on PyPI.
4. `bun` is not available on all canonical VMs (e.g., `epyc6`), breaking `cass-memory` installation via `bun`.

## Recommendations
- **Enable** all tools after correcting manifest.
- **Switch** `cass-memory` installation to `npm` for broader VM compatibility.
- **Switch** `serena` installation to git-based `uv tool install`.