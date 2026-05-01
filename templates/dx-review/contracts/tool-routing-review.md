## Tool Routing for Review

Use the canonical routing contract for review work:

- semantic discovery and feature location: `rg` / `fd` / direct reads first
- exact static/impact analysis: `llm-tldr`
- symbol-level inspection tied to a concrete code entity: `serena`

Fallback to direct shell/file inspection is allowed when:
- required MCP tool is unavailable in the current runtime, or
- one reasonable MCP attempt cannot answer the question.

Semantic tools are optional enrichment and must not block default discovery.
