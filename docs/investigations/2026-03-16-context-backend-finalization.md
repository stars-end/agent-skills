# Follow-up: Backend & Model Finalization for Context Stack (2026-03-16)

## 1. Embedding Model Comparison & Selection
To achieve "maximum benefit" for code-heavy repositories, we compared the leading Ollama-compatible models:

| Model | Context Window | Accuracy (MTEB) | Recommendation |
|-------|----------------|-----------------|----------------|
| **nomic-embed-text** | **8,192 tokens** | High | **Winner for Code.** The 8k window allows embedding entire classes/files without truncation logic. |
| **mxbai-embed-large** | 512 tokens | **Highest** | Not ideal for code. Requires complex chunking or loses structural context. |
| **all-minilm** | 256 tokens | Low | Too small. Only useful for short snippets or low-resource hardware. |

**Final Decision:** Standardize on **`nomic-embed-text`**. It is specifically trained for long-context retrieval and is the industry standard for local-first code RAG.

---

## 2. Indexing Cadence & Operational Impact
Based on source inspection of `context-plus` (`core/embedding-tracker.ts` and `core/embeddings.ts`):
- **Mechanism:** Uses `fs.watch` for realtime tracking and `SHA-based content hashing`.
- **Policy:** 
  - **Initial Index:** Full project traversal on server start.
  - **Updates:** Incremental. Only files with changed hashes are re-embedded.
- **Storage:** Per-repo storage in `.mcp_data/embeddings-cache.json`.
- **Recommendation:** Indexing is efficient enough to run on every file change (save). No "nightly re-index" is required for retrieval; the cache persists across sessions.

---

## 3. z.ai Adapter Compatibility & the "Ollama Gap"
We investigated if the existing `z.ai` stack (`https://api.z.ai/api/anthropic`) can reuse `context-plus`:
- **Problem:** `context-plus` is hard-coded to the **Ollama SDK**. The Ollama REST API (`/api/embed`) has a different schema than the OpenAI/Anthropic APIs (`/embeddings`).
- **Result:** **No direct reuse.** The `z.ai` adapter speaks Anthropic/OpenAI; `context-plus` speaks Ollama.
- **Workaround:** To use `z.ai` for embeddings, we would need a proxy (like LiteLLM) to emulate the Ollama API surface. 
- **Recommendation:** Maintain the **Split Architecture** but with **Tethered Local Execution**. Use local Ollama on each host (macmini, WSL, etc.) for live embeddings to avoid CPU starvation on epyc12. Use the existing `z.ai` stack for nightly "Enrichment" (labels/summaries) where schema-matching is easier via scripts.

---

## 4. Final Architecture Recommendation
We recommend **Option 3: Serena + Context+ Embeddings (Tethered Local) + Nightly GLM Enrichment**.

| Component | Target Backend | Role |
|-----------|----------------|------|
| **Serena** | Local LSP | Primary surgical editor & structural mapping. |
| **Context+ Embeddings** | Tethered Local Ollama | Semantic discovery & cross-session retrieval. Each VM runs its own `nomic-embed-text` instance. |
| **Context+ Chat** | **DISABLED** | Avoids the need for a chat-adapter/proxy. |
| **Enrichment** | Nightly GLM (`z.ai`) | Batch-updates semantic labels/clusters via direct API. |

---

## 5. Marginal Value Evidence
Why enable `context-plus` over Serena alone?
1. **Semantic Navigation:** Groups files by logic (e.g., "auth flow") even if filenames don't match. Ripgrep fails here.
2. **Concept Discovery:** Helps agents answer "how is transaction signing handled?" without knowing the exact variable names.
3. **Context Filling:** Automatically finds relevant code for RAG that `llm-tldr` (structural only) might miss.

---

## 6. auditable Sources
- **Embedding Benchmarks:** [MTEB Leaderboard](https://huggingface.co/spaces/mteb/leaderboard)
- **Ollama API Specs:** [Ollama GitHub Docs](https://github.com/ollama/ollama/blob/main/docs/api.md)
- **Context+ SDK Logic:** Verified in `src/core/embeddings.ts` (Ollama SDK import).
- **Z.ai Endpoint:** Verified in `scripts/adapters/cc-glm.sh`.
