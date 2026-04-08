# Tech Lead Review: Context-Plus Alternatives Analysis

**Topic:** contextplus-alternatives
**Date:** 2026-03-29

## Overview
This investigation aimed to identify and analyze the top 3 open-source MCP alternatives to `context-plus` given its significant shortcomings when utilized in local `dx-worktree` sub-paths (the "anchoring" flaw) and standard cross-repo agent routines. 

## Key Discoveries
The codebase was evaluated and multiple open-source repositories ([ceaksan/mcp-code-search](https://github.com/ceaksan/mcp-code-search), [zilliztech/claude-context](https://github.com/zilliztech/claude-context)) were cloned locally and examined. 

Three principal solutions were analyzed:
1. **llm-tldr**: Built-in support. Evaluated expanded capacity.
2. **mcp-code-search**: Local vector (LanceDB) + Tree-sitter. Tested via repository-cloning. 
3. **claude-context / Sourcegraph Cody**: External heavy-vector Database setups.

The core breakdown between them is **Local Isolated Storage vs Centralized Storage**. 

## Results & Findings
- **Cross-Repo Native**: Yes, **llm-tldr** natively solves the exact problem affecting `context-plus` by accepting `project` pathing parameters explicitly rather than attempting environment extrapolation from the IDE's root. Same applies to `mcp-code-search`, whose APIs parse indexed projects freely without binding to the runtime directory.
- **Cross-VM Stability**: Tools built around `LanceDB` (`mcp-code-search`) store vector data locally. Without shared network mounts (e.g. `~/bd`), cross-VM fleet agents will redundantly build indexes. For full VM-consistency, one must use Milvus (`claude-context`) or an external backend (`Sourcegraph`).

## Proposed Direction
Since `llm-tldr` natively achieves robust structural scanning and cross-repo referencing (and resides comfortably in our existing workflow), we propose officially adopting its `mcp_llm-tldr_semantic` capability going forward over adopting external servers or integrating completely new AST parsers lacking centralized support. 

## Open Decisions Needed from Tech Lead
1. Do we attempt to run `mcp-code-search` across VMs using a shared `~/.lancedb` mount (perhaps inside `~/bd/`)? 
2. Or do we explicitly codify `llm-tldr` as the sole semantic solution going forward to avoid vector-database dependencies?
