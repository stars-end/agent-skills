## Tool Routing for Review

Use the canonical routing contract for review work:

- semantic discovery and feature location: `rg` + direct file reads
- optional semantic hints: `scripts/semantic-search query` only when status is `ready`
- symbol-level inspection tied to a concrete code entity: `serena`

Fallback to direct shell/file inspection is allowed when:
- required MCP tool is unavailable in the current runtime, or
- one reasonable MCP attempt cannot answer the question.

If a required tool route is intentionally skipped, include:

`Tool routing exception: <reason>`
