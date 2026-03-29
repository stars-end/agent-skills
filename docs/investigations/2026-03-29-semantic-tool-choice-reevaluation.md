# Semantic Tool Choice Reevaluation — First Principles

**Date:** 2026-03-29
**Beads:** bd-rb0c.3 (subtask of bd-rb0c)
**Dependency:** bd-rb0c.1
**Author:** claude-opus-4-6

## Sources Inspected

| Source | SHA / Version | Type |
|--------|---------------|------|
| contextplus upstream | `2b5a6bde009c36fe01954777a9605b6df8bd3682` | Official repo (ForLoopCodes/contextplus) |
| llm-tldr upstream | HEAD of parcadei/llm-tldr | Official repo |
| serena upstream | HEAD of oraios/serena | Official repo |
| aider repomap | HEAD of Aider-AI/aider | External alternative |
| mcp-server-milvus | HEAD of zilliztech/mcp-server-milvus | External alternative (eliminated) |
| Internal: PR #423 | `d22578aa2d` | Cross-repo routing options memo |
| Internal: PR #419 | merged | Prior contextplus fix |
| Internal: PR #413 | Codex comparison artifact | |
| Internal: 2026-03-16 research | — | serena-contextplus-cass-research.md |
| Internal: 2026-03-16 backend finalization | — | context-backend-finalization.md |
| Internal: 2026-03-27 spec | — | mcp-tool-first-routing-and-cass-disposition.md |
| Internal: mcp-tools.yaml | — | Fleet manifest |

---

## 1. Why Did We Choose context-plus Originally?

The March 2026 research cycle (2026-03-16) evaluated three candidates. The rationale for choosing context-plus was:

1. **Semantic code search via vector embeddings** — the only tool in the stack that answers "where does this feature live?" by *meaning*, not by exact text match. Serena uses LSP/AST (structural, not semantic). llm-tldr uses tree-sitter structural analysis with optional FAISS-based semantic search.
2. **Memory graph** — Obsidian-style linking with decay-scored edges, providing cross-session concept recall.
3. **Spectral clustering** — `semantic_navigate` groups files by conceptual similarity, not directory structure.
4. **Complement to serena** — serena handles symbol-level edits; context-plus handles feature-level discovery. Clean lane separation.

The architecture decision was "serena + context-plus embeddings (tethered local Ollama) + nightly GLM enrichment."

## 2. Which Original Assumptions Have Weakened or Broken?

### 2.1 Ollama Dependency → Partially Resolved, Complexity Remains

The original research flagged the Ollama-only embedding backend as the primary integration risk. Upstream has since added an OpenAI-compatible provider (`CONTEXTPLUS_EMBED_PROVIDER=openai`), which we now use via OpenRouter (`openai/text-embedding-3-small`). This resolves the "Ollama gap" on hosts without local GPU.

**However**, the patched build + per-repo MCP entries + env var injection creates a multi-layer integration surface that requires ongoing maintenance. The manifest (`mcp-tools.yaml`) has 5 separate `context-plus-*` entries, each with per-IDE overrides for gemini-cli and antigravity. This is the highest per-tool config surface in the fleet.

### 2.2 Worktree Blindness → Structural, Not Incidental

PR #423 documents this clearly: each context-plus MCP entry is hardcoded to a canonical repo path (e.g., `~/agent-skills`). When an agent works in a worktree (`/tmp/agents/bd-xxxx/agent-skills`), context-plus continues indexing the untouched canonical clone, not the modified worktree.

This is **not an integration bug** — it follows directly from the upstream product shape. The `ROOT_DIR` is set once at server startup from the CLI argument or CWD. There is no tool-level parameter to redirect the root directory after startup. The four proposed fixes in PR #423 range from "upstream schema change" (Option 1) to "global daemon" (Option 4), none of which are implemented.

**Impact**: For any agent using `dx-worktree` (our standard workflow), context-plus indexes stale code. This fundamentally undermines first-tool routing reliability.

### 2.3 Cross-Repo Context → Broken for Multi-Repo Sessions

Each context-plus MCP server instance is bound to exactly one repo. In a multi-repo session (e.g., agent-skills + prime-radiant-ai), the agent must know which `context-plus-<repo>` server to call. Codex's flat MCP list presentation makes this worse — four identical-looking entries cause routing confusion (documented in the bd-e5z8 conformance failure).

### 2.4 Multi-Agent Safety → Partially Safe

The per-repo-entry model is actually safe for concurrent agents *as long as they are in different repos*. The symlink/hot-reload workarounds (Options 2/3 in PR #423) would break multi-agent safety but have not been implemented. Current state: safe but blind.

### 2.5 Embedding Cost and Latency

The OpenRouter embedding path introduces API cost and network latency for every semantic query. The original "tethered local Ollama" plan avoided this but required GPU on every host. Neither path is zero-cost.

## 3. What Unique Value Does context-plus Still Provide That llm-tldr Does Not?

| Capability | context-plus | llm-tldr |
|-----------|-------------|----------|
| Semantic code search (by meaning) | Yes — `semantic_code_search`, `semantic_identifier_search` via embeddings | Yes — `tldr semantic` via `bge-large-en-v1.5` FAISS index |
| Spectral clustering / concept grouping | Yes — `semantic_navigate` | No |
| Memory graph with decay | Yes — 6 memory tools | No |
| Feature hub / wikilink navigation | Yes — `get_feature_hub` | No |
| AST-based structural tree | Yes — `get_context_tree`, `get_file_skeleton` | Yes — `tldr tree`, `tldr structure` |
| Blast radius / impact analysis | Yes — `get_blast_radius` (text-search based) | Yes — `tldr impact` (call-graph based, more precise) |
| Static analysis | Yes — `run_static_analysis` (delegates to native tools) | Yes — `tldr diagnostics` |
| Control/data flow graphs | No | Yes — `tldr cfg`, `tldr dfg`, `tldr slice` (Layers 3-5) |
| Dead code detection | No | Yes — `tldr dead` |
| Program slicing | No | Yes — `tldr slice` |
| Code writing / propose_commit | Yes — `propose_commit` with validation | No (out of scope) |

**Unique context-plus capabilities that llm-tldr lacks:**
1. Spectral clustering (`semantic_navigate`)
2. Memory graph with decay-scored edges
3. Feature hub / wikilink navigation
4. Code writing with validation gates

**Key finding: llm-tldr now has its own semantic search layer** (FAISS with `bge-large-en-v1.5`), making the original "context-plus is the only semantic tool" assumption **no longer true**. The `tldr semantic` command and its MCP equivalent provide natural-language code search with structural context enrichment (call graph + data flow baked into embeddings).

## 4. Has llm-tldr Evolved Enough to Cover the Semantic Lane?

**Partially yes.** llm-tldr's semantic layer combines all 5 analysis layers (AST, call graph, CFG, DFG, PDG) into searchable embeddings. This is architecturally richer than context-plus's file-header + symbol-name approach because it encodes *behavioral* information, not just lexical/positional similarity.

**What llm-tldr still lacks:**
- No persistent memory graph (no cross-session concept recall)
- No spectral clustering (no "browse by concept" navigation)
- No feature hub / wikilink navigation

These are real gaps, but the question is whether they are *used in practice*. Based on internal routing contract compliance evidence:
- `semantic_code_search` and `get_context_tree` are the actually-routed tools
- `semantic_navigate`, memory graph tools, and `get_feature_hub` have near-zero observed agent usage in conformance testing
- The memory graph capabilities overlap with serena's `write_memory`/`read_memory` and the auto-memory system in Claude Code

## 5. Are context-plus Limitations Incidental or Structural?

**Structural.** The core issues follow from the upstream product shape:

1. **Single-root binding**: `ROOT_DIR` is set once at startup. This is a design choice, not a bug. Adding dynamic root selection would require upstream tool-schema changes (PR #423 Option 1).

2. **Per-repo MCP entries**: Required because of #1. Creates O(n) config entries for n repos, each with per-IDE variants. This config surface scales poorly.

3. **Embedding provider coupling**: While the OpenAI provider addition helped, the embedding lifecycle (cache in `.mcp_data/`, tracker via `fs.watch`) is tightly coupled to the single root directory. Worktrees don't get watched.

4. **No daemon/multi-root mode**: Unlike llm-tldr (which has a daemon with multi-project support), context-plus is one-server-per-root.

An incidental bug can be patched; a structural limitation requires upstream redesign or a fork. The worktree blindness and cross-repo issues are structural.

## 6. Realistic Options Now

### Option A: Keep context-plus as Canonical Semantic Default
- Continue patching per-repo MCP entries and per-IDE overrides
- Accept worktree blindness as a known limitation
- Hope upstream adds dynamic root selection
- **Pro**: No migration cost, preserves memory graph and spectral clustering
- **Con**: Worktree blindness undermines the first-tool-routing contract. Agents in worktrees get stale results, silently. High config surface.

### Option B: Keep context-plus but Demote to Experimental/Optional
- Remove from first-tool routing contract
- Keep installed for agents that explicitly request it
- Route semantic discovery to llm-tldr by default
- **Pro**: Honest about reliability. No migration risk — just a routing change. Preserves optionality.
- **Con**: Spectral clustering and memory graph become orphaned capabilities.

### Option C: Replace context-plus with llm-tldr for Default Semantic Lane
- llm-tldr becomes the canonical tool for both semantic discovery AND structural analysis
- Remove context-plus from the fleet manifest or mark as experimental
- **Pro**: One tool covers both lanes. llm-tldr's daemon mode, `--project` flag, and FAISS-based semantic search are production-ready. No worktree blindness (tldr indexes by project path argument per command).
- **Con**: Lose spectral clustering, memory graph, feature hub. Increased load on llm-tldr as both semantic and structural default.

### Option D: Replace with External Tool
- **mcp-server-milvus**: Not a code analysis tool. It's a vector DB connector. Requires external Milvus infrastructure. **Non-viable.**
- **aider repomap**: Excellent structural analysis (tree-sitter + PageRank-weighted tag ranking), but it's embedded in aider's codebase, not available as a standalone MCP server. Would require extraction/wrapping. **Non-viable without significant engineering.**
- No other open-source MCP-native semantic code discovery tool matches context-plus or llm-tldr's capability set.

## 7. Evaluation Matrix

| Tool / Option | Semantic Discovery Quality | Cross-Repo / Worktree Fit | Multi-Agent Safety | Operator Burden | Client UX / Routing Odds | Works Today | Recommendation |
|---------------|----------------------------|----------------------------|--------------------|-----------------|--------------------------|-------------|----------------|
| **context-plus (current)** | High (embeddings + spectral clustering + memory graph) | **Poor** — worktree-blind, single-root per instance, O(n) config entries | Safe (no shared state mutation) but stale in worktrees | **High** — patched build, 5 manifest entries, per-IDE overrides, OpenRouter API key | **Low** — Codex presentation clutter, worktree staleness causes silent bad results | Partial — works for canonical clones, broken for worktrees | Demote |
| **llm-tldr** | Good (FAISS + bge-large + 5-layer behavioral enrichment) | **Good** — `--project` flag per command, daemon with multi-project, no single-root lock-in | Safe (stateless per query, daemon per user) | **Low** — `uv tool install`, single `tldr-mcp` entry, no patching | **High** — single entry, works in all IDEs, no routing confusion | Yes | **Promote to default semantic lane** |
| **serena** | N/A (structural/symbol, not semantic) | Good — LSP-backed, project activation model | Safe | Low | High — clean single entry | Yes | Keep in current lane (symbol editing + memory) |
| **aider repomap** | Good (tree-sitter + PageRank) | Good (path-based) | N/A (not MCP) | **Very High** — not an MCP server, requires extraction | N/A | No | Non-viable without engineering |
| **mcp-server-milvus** | N/A (vector DB, not code analysis) | N/A | N/A | Very High (requires Milvus infra) | N/A | No | Non-viable |

## 8. Answer to Research Questions

### Q1: Why did we choose context-plus originally?
It was the only tool with vector-embedding-based semantic code search. llm-tldr was structural-only at the time. The "serena + context-plus" split was clean and defensible.

### Q2: Which assumptions have weakened or broken?
- "context-plus is the only semantic search tool" → **broken** (llm-tldr now has semantic search)
- "Local Ollama is the only embedding path" → **partially resolved** (OpenAI provider added)
- "One MCP entry per tool" → **broken** (requires 5 entries for 4 repos + base)
- "Worktrees are rare" → **broken** (worktrees are the standard workflow)

### Q3: Unique value context-plus still provides?
Spectral clustering, memory graph with decay, feature hub navigation. But these have near-zero observed agent usage.

### Q4: Has llm-tldr evolved enough?
Yes, for the default semantic lane. Its semantic search is architecturally richer (behavioral enrichment from 5 analysis layers). It lacks memory graph and spectral clustering, but those are unused in practice.

### Q5: Incidental or structural limitations?
**Structural.** Single-root binding, per-repo config multiplication, and worktree blindness follow from the upstream architecture.

### Q6: Realistic options?
A (keep), B (demote), C (replace with llm-tldr), D (external — non-viable).

### Q7: Best option per dimension?

| Dimension | Best Option |
|-----------|------------|
| Cross-repo correctness | B or C (both remove context-plus from default routing) |
| Worktree correctness | C (llm-tldr has no worktree blindness) |
| Cross-agent safety | A, B, or C (all safe; context-plus is safe but stale) |
| Low operator burden | C (eliminates 5 manifest entries + patched build) |
| High first-tool routing success | C (single llm-tldr entry, no presentation confusion) |

## 9. Note on Collapsed Options

Options B and C are very close in practice. The difference is:
- **B** keeps context-plus installed but removes it from the routing contract
- **C** additionally removes or disables context-plus from the fleet manifest

Given that context-plus's unique capabilities (spectral clustering, memory graph) are unused in practice, keeping it installed-but-unrouted adds config surface without benefit. **B and C collapse into the same practical recommendation**: demote context-plus and route semantic discovery to llm-tldr.

If spectral clustering or memory graph prove valuable in the future, context-plus can be re-enabled as an experimental opt-in. This is reversible.

## 10. Should Codex-Specific Patching for context-plus Stop?

**Yes.** Pending the outcome of this reevaluation, further patching of the context-plus build, additional per-IDE overrides, and conformance harness workarounds should stop. The engineering time is better spent ensuring llm-tldr's semantic capabilities are well-routed.

If this recommendation is accepted, the existing patched build can remain installed for opt-in use but should not receive further fleet-sync investment.

---

## Immediate Recommendation

**Demote context-plus from the canonical routing contract.** Change the MCP Tool-First Routing Contract (§5.4) so that semantic discovery routes to `llm-tldr` by default, not `context-plus`. Keep context-plus installed but mark it as experimental/optional in the manifest.

Concrete changes:
1. Update routing contract: `semantic repo discovery → llm-tldr` (not context-plus)
2. Mark all `context-plus-*` entries in `mcp-tools.yaml` as `enabled: false` or add `experimental: true`
3. Stop further Codex patching for context-plus
4. Keep the `context-plus` base entry for opt-in use

## Long-Term Recommendation

If spectral clustering or memory graph prove valuable for a concrete use case, evaluate whether llm-tldr can absorb those capabilities (upstream feature request) or re-enable context-plus as an opt-in experimental surface. Do not maintain two parallel semantic discovery tools in the canonical routing contract.

If upstream contextplus adds dynamic root selection (PR #423 Option 1), reassess. Until then, the worktree blindness makes it unsuitable as a reliable default.

## Decision

**Demote to experimental.** This is functionally equivalent to "replace with llm-tldr for the default lane" because the routing contract change is the same. The only difference is we don't delete the install — we preserve optionality.

## Migration Consequence

- Routing contract change in `publish-baseline.zsh` and CLAUDE.md: one text edit
- `mcp-tools.yaml`: mark `context-plus-*` entries as experimental or disabled
- No code changes to any app repo
- No agent retraining — the routing contract is injected via generated baselines
- Reversible: re-enable entries and restore routing text

This is a low-risk, high-clarity change. The main consequence is acknowledging that the prior decision was made before llm-tldr had semantic search and before worktree-first development was the standard workflow.
