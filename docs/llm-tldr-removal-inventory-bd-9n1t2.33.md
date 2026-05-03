# llm-tldr Removal Inventory (bd-9n1t2.33)

| Surface | Repo/Host | Decision | Reason | Owner Task |
|---|---|---|---|---|
| `extended/llm-tldr/SKILL.md` | agent-skills | remove | Active routing surface; superseded by `rg` + optional `scripts/semantic-search query` + `serena` | bd-9n1t2.33.2 |
| `scripts/tldr-*`, `scripts/tldr_contained_runtime.py` | agent-skills | remove | Legacy runtime and fallback wrappers for removed tool | bd-9n1t2.33.2 |
| `tests/test_tldr_daemon_fallback.py` | agent-skills | remove | Tests only covered removed runtime path | bd-9n1t2.33.2 |
| `configs/mcp-tools.yaml` `llm-tldr` tool block | agent-skills | remove | Canonical MCP manifest must not expose llm-tldr | bd-9n1t2.33.2 |
| `config-templates/fleet-sync-*` llm-tldr entries | agent-skills | remove | Prevent re-introducing llm-tldr on client render/apply | bd-9n1t2.33.2 |
| `fragments/dx-global-constraints.md` MCP routing language | agent-skills | remove/replace | New active contract: `rg` first, semantic hints optional/non-blocking, `semantic index unavailable; use rg` | bd-9n1t2.33.2 |
| Active skill docs under `core/`, `extended/`, `infra/`, `health/` | agent-skills | remove/replace | Remove llm-tldr guidance from agent-facing workflow docs | bd-9n1t2.33.2 |
| Generated `AGENTS.md`, `dist/*` | agent-skills | regenerate | Must reflect updated fragments and skill index | bd-9n1t2.33.2 |
| `AGENTS.md` + `fragments/*` active guidance refs | prime-radiant-ai | remove | Product repo baseline must not route agents to llm-tldr | bd-9n1t2.33.3 |
| `AGENTS.md` + `fragments/*` active guidance refs | affordabot | remove | Product repo baseline must not route agents to llm-tldr | bd-9n1t2.33.3 |
| `AGENTS.md` + `fragments/*` active guidance refs | llm-common | remove | Shared repo baseline must not route agents to llm-tldr | bd-9n1t2.33.3 |
| Historical specs/runbooks/evidence mentioning llm-tldr | all repos | tombstone (keep) | Historical records retained; not active routing instructions | bd-9n1t2.33.1 |
| Home MCP client configs (`~/.codex`, `~/.claude.json`, `~/.gemini/*`, `~/.config/opencode`) | host | inventory only | Uninstall/config cleanup owned by fleet lane; no local mutation in this lane | bd-9n1t2.33.4 |
| Local binaries (`~/.local/bin/llm-tldr`, `tldr`, `tldr-mcp`) | host | inventory only | Runtime uninstall owned by fleet lane | bd-9n1t2.33.4 |
