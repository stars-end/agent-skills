# Fleet Sync MCP Tool Restoration Research (bd-d8f4)

## Overview
This document captures the current status, installation methods, and validation requirements for the intended Fleet Sync MCP tool stack across all canonical VMs and IDE surfaces.

## Tool Status Summary

| Tool | Status | Current Version | Target Version | Runtime | Source Type |
|------|--------|-----------------|----------------|---------|-------------|
| `llm-tldr` | Working | 1.5.2 | 1.5.2 | Python | PyPI (stable) |
| `context-plus` | Broken | 0.4.2 (typo) | 1.0.7 | Node | npm (stable) |
| `cass-memory` | Broken | 1.0.0 (invalid) | git HEAD | Node | GitHub (moving) |
| `serena` | Broken | 0.9.1 (wrong) | git HEAD | Python | GitHub (moving) |

**Legend:**
- **PyPI (stable)** = Versioned releases on package registry
- **npm (stable)** = Versioned releases on npm registry
- **GitHub (moving)** = Git URL installation, no guaranteed version pinning

---

## Tool 1: llm-tldr
- **Status:** [VERIFIED] Working
- **Real Upstream:** [simonw/llm-tldr](https://github.com/simonw/llm-tldr) [INFERRED from package metadata]
- **Current Install Method:** `uv tool install "llm-tldr==1.5.2"` [VERIFIED on epyc6, macmini]
- **Required Runtime:** Python 3.12+ [VERIFIED]
- **Executable/MCP Entrypoint:** `llm-tldr` (Package provides `tldr` and `tldr-mcp` entrypoints) [VERIFIED]
- **Health Command:** `llm-tldr --version` [VERIFIED]
- **Config/Env Vars:** None required for baseline. [VERIFIED]
- **Cross-VM Notes:** [VERIFIED] Working on `epyc6` and `macmini`.

## Tool 2: context-plus
- **Status:** [INFERRED BROKEN] Package name typo in manifest
- **Real Upstream:** [ForLoopCodes/contextplus](https://github.com/ForLoopCodes/contextplus) [VERIFIED]
- **Real Package Name:** `contextplus` (on npm, NOT `@forloopcodes/contextplus`) [VERIFIED from npm registry]
- **Recommended Install Method:** `npm install -g contextplus@1.0.7` [RECOMMENDED]
- **Required Runtime:** Node.js 20+ [VERIFIED]
- **Executable/MCP Entrypoint:** `contextplus` [VERIFIED]
- **Health Command:** `contextplus --version` [VERIFIED]
- **Config/Env Vars:** `OLLAMA_EMBED_MODEL`, `OLLAMA_CHAT_MODEL` (Optional). [INFERRED]
- **Cross-VM Notes:** [INFERRED] Needs global npm install on all VMs.

## Tool 3: cass-memory
- **Status:** [VERIFIED BROKEN] Wrong package name, version, and binary name in manifest
- **Real Upstream:** [Dicklesworthstone/cass_memory_system](https://github.com/Dicklesworthstone/cass_memory_system) [VERIFIED]
- **Real Package Name:** `cass-memory` [INFERRED - not on npm, must use GitHub]
- **Recommended Install Method:** `npm install -g Dicklesworthstone/cass_memory_system` [RECOMMENDED for cross-VM compatibility]
- **Required Runtime:** Node.js 20+ (Bun recommended but npm works) [VERIFIED]
- **Executable/MCP Entrypoint:** `cm` [VERIFIED from repo docs]
- **Health Command:** `cm --version` [VERIFIED from repo docs]
- **Config/Env Vars:** `CASS_SHARE_MEMORY` (Opt-in). [INFERRED from repo docs]
- **Cross-VM Notes:** [VERIFIED] `bun` is missing on `epyc6`, [RECOMMENDED] use `npm` for broader VM compatibility.
- **Version Pinning:** [NOT AVAILABLE] Git installation means moving target, no stable version tag

## Tool 4: serena
- **Status:** [VERIFIED BROKEN] Points to wrong `serena` package on PyPI (AMQP client)
- **Real Upstream:** [oraios/serena](https://github.com/oraios/serena) [VERIFIED]
- **Real Package Name:** `serena` (MUST install from GitHub to avoid PyPI collision) [VERIFIED]
- **Recommended Install Method:** `uv tool install git+https://github.com/oraios/serena.git` [RECOMMENDED]
- **Required Runtime:** Python 3.12+ [VERIFIED]
- **Executable/MCP Entrypoint:** `serena start-mcp-server` [VERIFIED from repo docs]
- **Health Command:** `serena start-mcp-server --help` [VERIFIED from repo docs]
- **Config/Env Vars:** Uses `.serena/memories/` for state. [INFERRED from repo docs]
- **Cross-VM Notes:** [VERIFIED] Must avoid `serena` package on PyPI which is an unrelated AMQP client.
- **Version Pinning:** [NOT AVAILABLE] Git installation means moving target, manifest version `0.1.4` is arbitrary

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