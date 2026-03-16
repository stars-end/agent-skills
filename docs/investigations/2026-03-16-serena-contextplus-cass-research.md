# Context, Memory, and Semantic Navigation Research (2026-03-16)

## 1. Executive Recommendation
**FINAL VERDICT: CONDITIONAL_RECOMMENDATION**

Based on live local machine validation, source code inspection of upstream tools, and IDE configuration evaluation across the Linux canonical host:
- **`serena`**: Highly recommended. Provides surgically precise, LSP-backed AST symbol editing and semantic tokens without heavyweight vector infrastructure.
- **`context-plus`**: Recommended, but requires strict architecture decisions. It brings powerful vector-based meaning search (`nomic-embed-text`) and semantic navigation via spectral clustering, but hard-codes the `ollama` npm SDK. It does not natively support Anthropic or OpenAI API endpoints.
- **`cass-memory`**: Recommend pausing fleet-wide rollout. While the tool is healthy in some environments (e.g., macOS/Tech-Lead), it is currently in an **unhealthy local state on Linux** (missing `cass` CLI, empty playbook). 

**Target Architecture Recommendation**: 
`serena + context-plus embeddings + nightly GLM enrichment`
- `serena` handles structural reads and surgical symbol editing.
- `context-plus` should be configured for vector-embeddings against a *remote Ollama-compatible provider* or Centralized Ollama instance (`OLLAMA_HOST`).
- **Split Architecture:** Rely on lightweight Ollama embeddings (`nomic-embed-text`) for live semantic search, but offload heavy chat-based cluster labeling to a nightly GLM batch job rather than keeping an expensive chat model always-on.

---

## 2. Tool-by-Tool Findings

### 2.1 Serena
- **Actual execution:** Built on Python, integrates deeply with LSP (via `solidlsp`) for accurate AST-level manipulation and `semanticTokens` generation.
- **Role:** The core engine for surgical edits (insert after symbol, replace symbol, etc.). It does not rely on vector embeddings.
- **Local Status:** Successfully runs in both Claude Code and OpenCode. 

### 2.2 Context+
- **Actual execution:** Runs via Node/npx. Provides vector-based semantic code search, identifier embeddings, and memory graph functionality. 
- **Ollama Dependency:** Source inspection confirms it uses the `ollama` npm package directly (`import { Ollama } from "ollama"`). It does NOT natively support Anthropic or OpenAI SDKs. It relies on `OLLAMA_HOST`, `OLLAMA_EMBED_MODEL`, and `OLLAMA_CHAT_MODEL`.
- **Embeddings vs Chat:** 
  - *Embeddings* are required for `semantic_code_search`, `semantic_identifier_search`, and `memory_graph`.
  - *Chat* is required strictly for `semantic-navigate` (spectral clustering & labeling).
- **Local Status:** Connected and working as structural mapping.

### 2.3 CASS Memory
- **Actual execution:** CLI tool (`cm`).
- **Environment Drift:** Local Linux diagnostics (`cm doctor --json`) return `unhealthy`. The `cass` CLI is missing and the global playbook does not exist. This contrasts with the macOS environment where the tool is found and initialized.
- **MCP Status:** `cass-memory` is **not** present in the primary MCP configs (`~/.claude.json`, `~/.config/opencode/opencode.jsonc`, `~/.codex/config.toml`) on the Linux host. It was previously found in a secondary/stale `.opencode/config.json` file, but is not currently exposed to the agents.

---

## 3. Tradeoff Matrix

| Feature / Goal | `serena` | `context-plus` | `cass-memory` |
|----------------|----------|----------------|---------------|
| Semantic Code Search | No (AST/Name-based) | Yes (Vector Embeddings) | No |
| Symbol-level Editing | Yes (Best in class) | No | No |
| Cross-session Memory | Yes (File-based memories) | Yes (Memory Graph with Vectors) | Yes (CLI-native Playbooks) |
| Setup Complexity | Low | Medium (Requires Ollama/Adapter) | High (Requires manual init/training) |
| Architecture Fit | Immediate | Needs remote embeddings / proxy | Needs curation |

---

## 4. Exact Configuration Implications

### Claude Code (`~/.claude.json`)
Keep `serena` and `context-plus`. Ensure `OLLAMA_HOST` is injected into the `context-plus` environment.

### OpenCode (`~/.config/opencode/opencode.jsonc`)
Maintain current `serena` and `context-plus` entries. Do not add `cass-memory` until initialized.

### Codex (`~/.codex/config.toml`)
Mount `serena` and `context-plus`.

## 5. Residual Risks / Unknowns
- **Adapter Requirement:** To use our current primary models (GLM, Anthropic) with `context-plus`, we must provide an Ollama-compatible translation layer (e.g., `litellm` or a simple reverse proxy).
- **CASS Bootstrap:** Fleet-wide rollout on Linux is currently blocked by the missing `cass` crate and uninitialized playbooks.
