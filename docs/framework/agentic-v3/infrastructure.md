# Infrastructure & Resilience Components

## State Recovery Hook (`post-merge` / `post-checkout`)
Automatically keeps the local environment in sync with the team state.
- **Actions:** Runs `bd import`, `pnpm install`, and `git submodule update`.
- **Why:** Prevents 'Ghost Commit' errors and lockfile desync.

## Lockfile Guardian (GitHub Action)
A bot that fixes the most common PR toil: missing lockfile updates.
- **Logic:** If `pyproject.toml` changed but not the lock, use GLM-4.7 to resolve and commit the fix.

## Semantic Environment Resolver
A library in `llm-common` that returns the correct service URLs based on the runtime context.
- **Contexts:** `local`, `railway-pr`, `railway-dev`, `jules-sandbox`.
- **Eliminates:** Hardcoded `localhost:8000` strings.

## Permission Sentinel
A `pre-commit` hook that enforces execution bits on all scripts.
- **Action:** `chmod +x scripts/*.sh`.

