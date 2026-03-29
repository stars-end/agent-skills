# ContextPlus Cross-Repo & Cross-Agent Routing Options

**Date:** 2026-03-29

## The Problem

With the transition to a fleet-synced MCP map, we encountered routing and presentation issues involving `contextplus` that manifest differently across IDEs:

1. **Codex Presentation Clash**: Having four identical `context-plus-*` repo-scoped servers in a flat MCP list creates a cluttered selection surface, causing Codex to fail semantic-routing conformance cases (e.g. `bd-e5z8` test rerun). 
2. **Worktree Blindness**: For IDEs like OpenCode/Claude that use the explicit repo-scoped backend entries (e.g. `context-plus-agent-skills`), the path is hardcoded to canonical directories (`~/agent-skills`). When doing cross-repo development or utilizing `dx-worktree` isolates (e.g., `/tmp/agents/bd-xxxx/agent-skills`), the MCP server continues reading the untouched canonical repo rather than the modified worktree code.
3. **Cross-Repo Context**: Codex uses a single `context-plus` entry configured without an explicit path argument. This causes the backend to root itself at the initial CWD. If an agent transitions across repositories in a single session, the MCP instance remains anchored and misses context from the newly traversed repos.

## Proposed Options

### Option 1: Dynamic Workspace API (Tool-Level Paths)
Modify the `contextplus` patched build to accept an optional `cwd` or `repository_path` argument on its internal tool calls (e.g., `search_memory_graph`, `get_context_tree`).
- **Pros:** A single `context-plus` MCP entry satisfies Codex without presentation confusion. Agents can dynamically switch roots by providing the worktree path directly inside tool calls, perfectly supporting `/tmp/agents/bd-xxxx/` worktrees across any repository boundary.
- **Cons:** Requires a tool-schema contract change and reliable caller behavior so agents actually pass the `repository_path` on semantic calls, not just a backend patching change.

### Option 2: Agent-Lifecycle Injection (Hot-Reload)
When `dx-worktree` creates a new environment, a script dynamically overwrites `~/.codex/config.toml` (and other local IDE configs) to point the `context-plus` MCP argument directly at the new worktree path. A `SIGHUP` or restart signal is then sent to hard-reload the IDE's MCP servers mid-session.
- **Pros:** Requires zero upstream changes to the `contextplus` tool logic. Guarantees the MCP server strictly indexes the active worktree path.
- **Cons:** Rewriting `~/.codex/config.toml` or other shared home-scoped config from `dx-worktree` is shared-state mutation. Shared home-scoped config is unsafe for concurrent agents unless session-local. On a multi-agent VM, one agent can stomp another agent's active root, making it fundamentally unsafe. Furthermore, not all IDEs support seamless headless MCP hot-reloading mid-session without dropping conversational context.

### Option 3: Virtual Workspace Symlinking
Introduce a stable, fleet-wide symlink (e.g., `~/.active-dx-worktree`) that is automatically updated by `dx-worktree` commands to point to the most recently created or active worktree. The `context-plus` MCP config is anchored centrally to this symlink.
- **Pros:** Zero changes required to the node.js tool. Codex is clean with one visible entry pointing to the symlink.
- **Cons:** Inherently race-condition prone for concurrent agents running tests on the same VM. Worktree switches during active conversation would still require restarting the MCP server.

### Option 4: "Thin Client" Global Daemon
Deploy a persistent background `contextplus-daemon` that recursively indexes all canonical repos seamlessly alongside `/tmp/agents/*`. The MCP servers exposed to the various IDEs simply act as thin routing clients that proxy read requests to the global daemon.
- **Pros:** Blazing fast agent startup since the re-indexing penalty is mitigated. No IDE restart required when switching workspaces.
- **Cons:** Prohibitive API token footprint (indexing unbounded sets of temporary worktrees via OpenRouter). Introduces heavy background infrastructure complexity.

## Evaluation & Recommendation

**Immediate Recommendation**
Keep the Codex single-alias presentation and finish the re-test. This provides an immediate validation step without structural risk.

**Long-Term Recommendation**
Pursue upstream dynamic root selection / workspace API (**Option 1**). This is the cleanest architecture because it dynamically resolves at call time. It requires product-shape/upstream changes but solves the `dx-worktree` isolation limitation without relying on brittle, shared-state mutation tactics.
