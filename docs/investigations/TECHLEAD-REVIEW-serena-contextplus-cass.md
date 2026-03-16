# Tech Lead Review: Serena, Context+, and CASS Memory Stack

## Overview
This investigation evaluated the semantic/memory stack across canonical hosts. We have finalized the backend architecture and model selection to maximize code-discovery benefit while minimizing infra complexity.

## Final Decisions
1. **Embedding Model:** Standardize on **`nomic-embed-text`**. Its 8,192 token context window is the only viable option for large code files without losing structural context.
2. **Backend Architecture:** **Option 3 (Split Architecture)**. 
   - Tethered Local Ollama (each host runs its own instance) for live embeddings to prevent epyc12 CPU starvation.
   - Nightly GLM (`z.ai`) for heavy enrichment/labeling.
3. **Indexing Policy:** Realtime incremental indexing. `context-plus` handles this via file watchers and content-hashing; no manual nightly re-index is required for retrieval.
4. **Adapter Decision:** Do not build a LiteLLM adapter. Instead, disable live chat in `context-plus` (`OLLAMA_CHAT_MODEL=none`) to avoid schema mismatches with `z.ai`.
5. **CASS Memory Cleanup:** Remove `cass-memory` from the stale legacy **`~/.opencode/config.json`** file. Confirmed active configs are already clean.

## Architecture Summary
- **Serena:** Local LSP (Surgical editing).
- **Context+:** Tethered Local Ollama (Semantic discovery).
- **Enrichment:** Z.ai Batch (Nightly metadata updates).

## Auditable Research
- [Primary Research Doc](docs/investigations/2026-03-16-serena-contextplus-cass-research.md)
- [Backend Finalization Doc](docs/investigations/2026-03-16-context-backend-finalization.md)
