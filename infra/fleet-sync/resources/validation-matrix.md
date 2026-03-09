# Fleet Sync Validation Matrix

| Mode | Layer | Commands | Status |
|-------------|------------------------------|-----------------------|------------------------------------------|----------------|
| Layer 1 | cm --version | ✅ | Runtime health | macmini: pass | |
| | cm quickstart --json | ✅ | Runtime health | macmini: Pass | |
| | cm doctor --json | ✅ | Runtime health | macmini: Pass | |
| tldr-mcp --version | ✅ | Runtime health | macmini: Pass | |
| llm-tldr --version | ✅ | Runtime health | macmini: Pass | |
| | tldr-mcp --version | ✅ | Runtime health | epyc6: ✅ | |
| | llm-tldr --version | ✅ | Runtime health | homedesktop-wsl: Not verified | Inferred from shared config |
| | tldr-mcp --version | ✅ | Runtime health | homedesktop-wsl: Not verified | inferred from shared config paths |
            | contextplus --version | N/a | Package not found | epyc6: Not verified | npm install failed with 404 |
            | serena --version | N/a | Entrypoint missing | Not verified | entrypoint via `serena start-mcp-server` missing |
            | serena --version | N/a | Package installation blocked ( PyPI collision) | Not verified | Entrypoint via `uv tool install git+https://github.com/oraios/serena.git` missing
            | serena start-mcp-server --help | cannot verify executable entrypoint
            | `cm --version` | health passes on all canonical hosts
            | `tldr-mcp --version || llm-tldr --version` | health passes on all canonical hosts
            - For llm-tldr: test `codex mcp list` / etc.
            - for llm-tldr: context retrieval, test `cm context "<task>" --json` to verify MCP server visibility
            - For llm-tldr context: test `llm-tldr --json` to verify the token reduction claims are accurate
            - If context-plus is blocked, document the blocker
            - If serena is blocked, document the blocker

            - If tools are disabled but manifest disabled_reason must be updated first
