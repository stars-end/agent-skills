# Fleet Brain Implementation Specification (V1.1)

## 1. Overview
Centralized Agent Intelligence Gateway on `epyc12`. This spec addresses multi-branch safety, SPOF mitigation, and secure secret injection.

## 2. Core Components (Hybrid Deployment)

### 2.1 Perception & Memory (Centralized on epyc12)
- **llm-tldr**: Structural summaries and semantic search.
- **CMS**: Shared procedural playbook and trauma registry.
- **Why**: These depend on repo-wide history and "collective wisdom," not local branch state.

### 2.2 Symbolic Operations (Local to Worker)
- **Serena / LSPs**: Language servers MUST run on the local worker VM.
- **Reasoning**: To ensure accuracy against uncommitted worktree state and per-VM branch drift (resolving P1 finding). Centralized LSPs would produce stale results for local changes.

## 3. Infrastructure: The "Fleet Brain" Gateway

### 3.1 Availability & Degraded Mode (Resolving P1 SPOF)
- **Primary**: Agents use `http://epyc12:3000/sse`.
- **Fallback**: If the gateway is unreachable, agents MUST fall back to local `grep_search`, `glob`, and `read_file`.
- **Contract**: The gateway is an *accelerator*, not a *blocker*. Agents must remain functional in "Offline Mode."

### 3.2 Secret Injection (Resolving P1 Secrets)
- **Bootstrap**: Use `1Password Service Accounts`.
- **Security**: Service tokens are stored via `systemd-creds` (encrypted at rest).
- **Injection**: systemd units use `LoadCredential=` to inject secrets into the service environment without exposing them in `ps` or environment logs.

## 4. Operational Excellence

### 4.1 Security & AuthZ (Resolving P2 Security)
- **Transport**: Tailscale encrypted tunnel.
- **Handshake**: The Gateway requires an `X-MCP-API-KEY` header.
- **Audit**: All remote tool calls are logged to a central `brain-audit.log` on `epyc12`.

### 4.2 Decoupled Documentation (Resolving P2 Coupling)
- **Caching**: `make publish-baseline` queries a local `~/.cache/mcp-tools.json`.
- **Refresh**: A background cron updates the cache if the gateway is up.
- **Build Safety**: Documentation build defaults to the cache if the gateway is down, preventing build-time coupling.

## 5. Beads Implementation Plan
- **bd-d8f4**: Fleet Brain Epic
- **bd-d8f4.1**: Infrastructure (systemd-creds + supergateway)
- **bd-d8f4.2**: Logic (Centralized Perception Cloud Bridge)
- **bd-d8f4.3**: Config (Local LSP + Centralized MCP symlink mapping)
- **bd-d8f4.4**: Docs (Cached manifest generation)
