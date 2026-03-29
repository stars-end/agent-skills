# Context-Plus Alternatives: Deep Dive & Cross-Repo/Cross-VM Analysis

**Date:** 2026-03-29
**Topic:** Semantic Discovery MCP Alternatives

## Objective
Evaluate the top 3 alternatives to `context-plus` for Semantic Code Discovery, focusing on:
1. Robustness
2. Cross-repo compatibility natively
3. Cross-agent-IDE and Cross-VM consistency

## Tool 1: `llm-tldr` (Expanded Usage)
`llm-tldr` is already in our fleet, primarily used for exact structure and static analysis traces. We evaluated extending its `mcp_llm-tldr_semantic` capability to assume all context discovery.

- **Robustness**: High. It relies on standard embeddings over strict function/class AST definitions rather than arbitrary chunks.
- **Cross-Repo**: **NATIVE**. Every tool in `llm-tldr` accepts a `project: <path>` parameter instead of relying on the IDE's launch CWD. An agent can seamlessly query `/tmp/agents/bd-xxxx/first-repo` and then `/tmp/agents/bd-xxxx/second-repo` in the same session.
- **Cross-VM / IDE Consistency**: Medium-High. Indexes are built on-the-fly or cached locally per repo path. If path structures deviate across VMs, the cache must rebuild, but the semantic functionality remains perfectly consistent across Cursor, Claude Code, etc.

## Tool 2: `ceaksan/mcp-code-search` (Local AST + LanceDB)
A promising open-source implementation that utilizes `Tree-sitter` for AST-aware chunking and `LanceDB` for hybrid search.

- **Robustness**: High. Combines vector search with traditional FTS (keyword search) through LanceDB.
- **Cross-Repo**: **NATIVE**. Evaluated the source code (`server.py`); the MCP exposes an explicit `index_directory(path: str)` tool. It iterates across all indexed `project_path` entries dynamically when searching. It does not bind to IDE startup CWD.
- **Cross-VM / IDE Consistency**: Medium-Low. Vector embeddings are stored locally inside a LanceDB directory. While it works identically across IDE clients on the *same* VM, cross-VM state requires mounting or synchronizing the database artifact explicitly (else each VM rebuilds the embeddings from scratch).

## Tool 3: `zilliztech/claude-context` (or Sourcegraph Cody)
An enterprise-tier pattern where the MCP server bridges an external vector database (Milvus/Zilliz or Sourcegraph's backend).

- **Robustness**: Enterprise-Grade. Offloads memory pressure and AST processing entirely. Can digest millions of lines of code.
- **Cross-Repo**: Highly scalable. Repositories are segmented by metadata inside the centralized vector space. The agent queries the centralized index without referencing local paths at all.
- **Cross-VM / IDE Consistency**: **HIGHEST**. Because the state lives in a centralized DB backend rather than the VM's file system, agents distributed across the entire fleet seamlessly share the exact same context indices, totally unaffected by which `dx-worktree` cluster they reside on.

## Recommendations
For maximum **Cross-Repo** ergonomics in local `dx-worktree` scopes, **`llm-tldr`** and **`mcp-code-search`** adequately solve the CWD-anchoring flaw of `context-plus`. 

However, if **Cross-VM consistency** without re-indexing overhead is a strict requirement, navigating toward an external-DB pattern like **`claude-context`** or **Sourcegraph** is mandatory. 

Given our current constraints and preference for self-contained agent loops, transitioning semantic discovery to our existing **`llm-tldr`** configuration avoids introducing heavy external DB dependencies while immediately resolving the cross-repo CWD blockers.
