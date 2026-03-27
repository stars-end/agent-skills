# Railway Helper Contract

Canonical shared helper surface for Railway auth loading and non-interactive
command execution across agent-skills and downstream repos.

## Shared Libraries

| Library | Purpose |
|---------|---------|
| `scripts/lib/dx-auth.sh` | 1Password service-account token loading, secret caching |
| `scripts/lib/dx-railway.sh` | Railway context resolution, auth normalization, command execution |

## Contract Surface

### Auth Loading

```bash
source "$HELPER_DIR/lib/dx-auth.sh"
source "$HELPER_DIR/lib/dx-railway.sh"

dx_railway_normalize_auth
```

Loads `RAILWAY_API_TOKEN` from (in priority order):
1. Already-exported `RAILWAY_API_TOKEN`
2. Compatibility fallback: `RAILWAY_TOKEN` -> `RAILWAY_API_TOKEN`
3. 1Password via `dx_auth_load_railway_api_token` (cached 24h)

### Context Resolution

```bash
CONTEXT_FILE="$(dx_railway_resolve_context_file)"
```

Searches (in priority order):
1. `$DX_RAILWAY_CONTEXT_FILE` (explicit override)
2. `<worktree-context-base>/<beads-id>/<repo>/railway-context.env`
3. `.dx/railway-context.env` (cwd, returned even if absent)

### Command Execution

```bash
dx_railway_exec "$PROJECT_ID" "$ENV_NAME" "$SERVICE_NAME" -- command args
```

Behavior:
- When `PROJECT_ID` is set: `railway run -p/-e/-s`
- When `PROJECT_ID` is empty and `railway status` works: `railway run -s`
- Otherwise: returns 1 (caller decides how to BLOCKED)

## Entry-Point Scripts

| Script | Purpose |
|--------|---------|
| `scripts/dx-load-railway-auth.sh` | Auth-only wrapper: `-- <cmd>` or `--check` |
| `scripts/dx-railway-run.sh` | General command execution in Railway context |
| `scripts/dx-railway-postgres.sh` | Postgres-specific operations (query, psql, backend-python) |

## Required Inputs

`-p` (project), `-e` (environment), `-s` (service) are required for fully
non-interactive execution. These come from:

1. **Explicit CLI flags** (highest priority)
2. **Seeded context file** (worktree or `.dx/railway-context.env`)
3. **Environment variables** (`DX_RAILWAY_PROJECT_ID`, `RAILWAY_PROJECT_ID`, etc.)
4. **Repo-local wrapper defaults** (lowest priority, repo-specific)

Ambient `railway link` state from another repo is **not** sufficient evidence
of correct target context.

## Downstream Adoption

A repo-local wrapper should be thin:

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/dx-auth.sh"
source "$SCRIPT_DIR/lib/dx-railway.sh"

# Repo-specific defaults only
PROJECT_ID="${MY_REPO_RAILWAY_PROJECT_ID:-}"
ENV_NAME="${MY_REPO_RAILWAY_ENV:-dev}"
SERVICE_NAME="${MY_REPO_RAILWAY_SERVICE:-backend}"

dx_railway_normalize_auth
exec dx_railway_exec "$PROJECT_ID" "$ENV_NAME" "$SERVICE_NAME" -- "$@"
```

The shared libraries are the canonical source. The repo-local wrapper owns
only its own default naming policy.

## Consolidation History

Before this contract, `resolve_context_file()` was duplicated across
`dx-railway-run.sh` and `dx-railway-postgres.sh` with minor behavioral
differences. Both now source `dx_railway_resolve_context_file` from
`scripts/lib/dx-railway.sh`.
