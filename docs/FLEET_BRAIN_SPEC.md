# Fleet Brain Implementation Specification (V1.0)

## 1. Overview
This specification defines the architecture for a **Centralized Agent Intelligence Gateway** on `epyc12`. It collapses the complexity of a 16-agent fintech fleet (across 4 VMs and 5 repos) into a single, robust, and low-maintenance control plane.

## 2. Core Components

### 2.1 Perception Layer (llm-tldr)
- **Role**: Context extraction and program slicing.
- **Implementation**: `llm-tldr` daemon running on `epyc12`.
- **Value**: 95% token savings and surgical logic tracing.

### 2.2 Symbolic Layer (Serena)
- **Role**: Semantic code navigation and editing.
- **Implementation**: MCP server using LSPs (Pyright, gopls, rust-analyzer).
- **Value**: Type-safe, IDE-level precision for autonomous edits.

### 2.3 Memory Layer (CMS)
- **Role**: Procedural playbook and "Trauma Registry."
- **Implementation**: `cass_memory_system` indexing session logs across all VMs.
- **Value**: Cross-agent learning and "confidence decay" for self-correcting rules.

### 2.4 Navigation Layer (Context+)
- **Role**: High-level feature mapping and clustering.
- **Implementation**: "Feature Hubs" (Wikilinks) to group cross-repo logic.
- **Value**: Solving "Cross-Repo Blindness" for solo agents.

## 3. Infrastructure: The "Fleet Brain" Gateway

### 3.1 The Master (epyc12)
- Runs all "heavy" logic and language servers.
- Exposes a unified MCP Gateway on `port 3000` via `supergateway` (HTTP/SSE).
- Handles all API keys ($ZAI_API_KEY, $OPENROUTER_API_KEY) via `op cli`.

### 3.2 The Workers (macmini, etc.)
- "Thin Clients" pointing to `http://epyc12:3000/sse`.
- Zero local dependencies (no LSPs or heavy Python envs required).

## 4. Operational Excellence

### 4.1 Loud Failure & Self-Healing
- All tools managed by `systemd --user` with `Restart=always`.
- Failure of the gateway is "Loud" (Connection Refused), eliminating "Drunk Agent" behavior.

### 4.2 Zero-Maintenance Sync
- A single master `fleet.mcp.json` in `agent-skills` repo.
- Global IDE configs (Claude, Cursor, OpenCode) are symlinked to this file.

### 4.3 Live Manifest (AGENTS.md)
- `make publish-baseline` is updated to query the live `/tools` endpoint of the Gateway.
- Guaranteed sync between documentation and capability.

## 5. Security
- Transport over Tailscale (internal IP only).
- Secrets isolated to the `epyc12` environment.
