---
name: devops-dx
description: |
  GitHub/Railway housekeeping for CI env/secret management and DX maintenance.
  Use when setting or auditing GitHub Actions variables/secrets, syncing Railway env → GitHub, auditing cross-repo GitHub Actions failure groups, or fixing CI failures due to missing env.
tags: [devops, github, auth, env, secrets, ci, railway]
allowed-tools:
  - Bash(gh:*)
  - Bash(railway:*)
  - Bash(curl:*)
  - Bash(scripts/dx-gh-actions-audit.py:*)
  - Bash(scripts/dx-audit.sh:*)
  - Bash(scripts/dx-founder-daily.sh:*)
  - Read
  - Bash(jq:*)
---

# DevOps DX Helper

Lightweight playbook for CI/Railway env hygiene. Examples use this repo's Beads prefix (bd-); swap for your repo.

## Cross-Repo GitHub Actions Failure Audit

Use this when the question is "what CI failures are still active across the canonical repos?" or when `dx-audit`/founder-daily claims GitHub Actions failures exist.

Run the collector directly for the most detailed machine-readable report:

```bash
~/agent-skills/scripts/dx-gh-actions-audit.py --json
```

Run the weekly audit surface when you need the same signal as automation:

```bash
~/agent-skills/scripts/dx-audit.sh --json | jq '.summary.github_actions, .github_actions.active_groups[:5]'
```

Run founder-daily when you need the founder-facing briefing payload:

```bash
~/agent-skills/scripts/dx-founder-daily.sh --json | jq '.github.failure_groups[:5], .github.repo_errors'
```

### Output Contract

- `active_groups`: grouped failures that still matter on the default branch or an open PR branch/SHA.
- `stale_groups`: historical failures superseded by success or on irrelevant closed/non-default branches.
- `repo_errors`: repos the collector could not inspect; treat these as coverage gaps, not proof of green CI.
- `summary.coverage_repo_errors`: count of repos with failed coverage.
- `latest_failure.run_url`: first URL to inspect before opening individual workflow logs.

### Tuning

The automation surfaces default to a smaller, faster sample. Increase limits for manual investigations:

```bash
DX_GH_FAILURE_AUDIT_FAILED_LIMIT=30 DX_GH_FAILURE_AUDIT_RECENT_LIMIT=80 \
  ~/agent-skills/scripts/dx-audit.sh --json | jq '.summary.github_actions'
```

### Triage Rule

Fix `active_groups` first. Do not spend agent time on `stale_groups` unless the same signature reappears as active. If `repo_errors` is non-empty, fix collector coverage/auth before concluding the weekly audit is clean.

## Railway GraphQL Integration (NEW)

For comprehensive Railway environment validation, use the GraphQL-based validation script:

```bash
# Validate linked Railway project
~/.agent/skills/devops-dx/scripts/validate_railway_env.sh

# Validate specific project
~/.agent/skills/devops-dx/scripts/validate_railway_env.sh --project-id <PROJECT_ID>

# Validate specific service
~/.agent/skills/devops-dx/scripts/validate_railway_env.sh --service <SERVICE_NAME>
```

**Features:**
- Fetches full environment configuration via GraphQL API
- Detects staged (unapplied) changes
- Validates required environment variables
- Checks for build/start command conflicts
- Lists all services and their configuration
- Cross-agent compatible (works with skills-native and MCP agents)

## Common Tasks

- **Set GitHub Actions variables** (non-secret paths, stub fixtures):
  - `gh variable set CLERK_TEST_JWKS_PATH --body "frontend/e2e-smoke/fixtures/clerk-test-jwks.json"`
  - `gh variable set CLERK_TEST_PRIVATE_KEY_PATH --body "frontend/e2e-smoke/fixtures/clerk-test-private.pem"`

- **Set GitHub Actions secrets** (API keys, tokens):
  - `gh secret set ZAI_API_KEY <<<"…"`
  - `gh secret set OPENAI_API_KEY <<<"…"`

- **Sync Railway → GitHub secrets** (if already stored in Railway):
  - `scripts/sync_env_to_github.sh <environment> [service]`
    - Copies Railway env vars to GitHub repo secrets (keys sanitized for GH).

## When CI Fails for Missing Env

1) Identify missing var from logs (e.g., `CLERK_TEST_JWKS_PATH missing`).
2) Decide scope:
   - CI-only → set via `gh variable/secret set`.
   - Runtime (Railway) → set in Railway dashboard or `railway variables set`.
3) Re-run the affected workflow: `gh workflow run CI --ref master`.

## Cross-Repo GitHub Actions Failure Audit

For CI failure triage across canonical repos, use the shared audit surface:

```bash
scripts/dx-gh-actions-audit.py --json
```

Useful knobs:

- `DX_GH_FAILURE_AUDIT_FAILED_LIMIT`: how many failed workflow runs to inspect per repo
- `DX_GH_FAILURE_AUDIT_RECENT_LIMIT`: how many recent workflow runs to sample per repo

Output contract:

- `active_groups`: current recurring failure groups
- `stale_groups`: historical groups no longer active
- `repo_errors`: repo-level GitHub/API failures
- `coverage_errors`: missing workflow or audit coverage

Weekly `dx-audit` reports include active cross-repo GitHub Actions failure groups. Use this audit before opening one-off CI remediation work so agents do not chase the same failure independently in multiple repos.

## Notes

- Keep stub/test fixtures in GH Actions vars, not Railway.
- Use Railway for production secrets; keep CI-only secrets separate.
- For multi-repo, reuse this skill and adjust variable names/prefixes per repo.
