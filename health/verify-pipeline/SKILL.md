---
name: verify-pipeline
description: |
  Run project verification checks using standard Makefile targets.
  Use when user says "verify pipeline", "check my work", "run tests", or "validate changes".
  Wraps `make verify-pipeline` (E2E), `make verify-analysis` (Logic), or `make verify-all`.
  Ensures environment constraints (e.g. Railway Shell) are met.
tags: [workflow, testing, verification, makefile, railway]
allowed-tools:
  - Bash(make verify-*)
  - Bash(railway run *)
  - Bash(railway:*)
  - Bash(curl:*)
  - Read
---

# Verify Pipeline

Standardized verification workflow for Affordabot and V3 projects.

## Purpose

Run standardized verification scripts defined in the project `Makefile`.
Ensures consistency between local dev, CI, and agent workflows.

## When to Use This Skill

**Trigger phrases:**
- "verify pipeline"
- "check my work"
- "run verification"
- "test the changes"
- "did I break anything?"

**Use when:**
- After implementing a features (especially Phase 5 search/RAG)
- Before creating a PR
- When debugging "State of the World"

## PREREQUISITE CHECKLIST

Before running verification, ensure all prerequisites are met:

### 1. Railway Context Check

**Required for:** `verify-pipeline`, `verify-gate`, `smoke-*` targets

Check if Railway environment is configured:

```bash
# Check for Railway environment
if [ -n "$RAILWAY_ENVIRONMENT" ] || [ -n "$RAILWAY_TOKEN" ]; then
  echo "✅ Railway context detected"
else
  echo "⚠️ No Railway context - run 'railway shell' or set RAILWAY_TOKEN"
fi
```

**How to fix:**
```bash
# Option 1: Interactive shell (recommended for local dev)
railway shell

# Option 2: Set token from 1Password (for CI/automation)
export RAILWAY_TOKEN=$(op read "op://Railway-Delivery/RAILWAY_TOKEN")
```

### 2. Dev Server Check

**Required for:** `verify-dev`, `smoke-*` targets that hit localhost

Check if dev server is running:

```bash
# Check if dev server is responding
curl -s http://localhost:8000/health >/dev/null 2>&1 && echo "✅ Dev server running" || echo "⚠️ Dev server not running"
```

**How to fix:**
```bash
# Start dev server in background
make dev &

# Or use the full command
uvicorn app.main:app --reload --port 8000 &
```

### 3. Dependencies Check

**Required for:** All verification targets

Check if dependencies are installed:

```bash
# Check for Poetry/pnpm lock files
if [ -f "pyproject.toml" ]; then
  poetry env info >/dev/null 2>&1 && echo "✅ Poetry env ready" || echo "⚠️ Run 'poetry install'"
elif [ -f "package.json" ]; then
  [ -d "node_modules" ] && echo "✅ Node modules installed" || echo "⚠️ Run 'pnpm install'"
fi
```

**How to fix:**
```bash
# Python projects
poetry install

# Node projects
pnpm install
```

## Verification Targets

| Target | Description | Environment | Duration |
|--------|-------------|-------------|----------|
| `verify-gate` | Pre-merge gate (lint + unit + smoke) | Local/CI | ~2 min |
| `verify-dev` | Development verification (no DB) | Local | ~30 sec |
| `verify-pipeline` | E2E RAG Pipeline (requires DB) | Railway Shell | ~5 min |
| `verify-analysis` | Legislation Logic (Integration) | Railway Shell | ~3 min |
| `verify-auth` | Auth Config validation | Local/Railway | ~1 min |
| `verify-all` | All verification targets | Railway Shell | ~10 min |
| `smoke-api` | API health check smoke test | Local/Railway | ~10 sec |
| `smoke-e2e` | End-to-end smoke test | Railway Shell | ~1 min |
| `ci` | Full CI pipeline | CI only | ~15 min |

### Target Selection Guide

```
Before commit:     make verify-dev
Before PR:         make verify-gate
After deployment:  make smoke-api smoke-e2e
Full validation:   make verify-all
```

## Workflow

### 1. Identify Verification Targets

Check `Makefile` for available `verify-*` targets:

```bash
grep "^verify-" Makefile
grep "^smoke-" Makefile
```

### 2. Run Prerequisite Checks

Run the prerequisite checklist above before executing verification.

### 3. Run Verification

**Quick check (before commit):**
```bash
make verify-dev
```

**Pre-merge gate:**
```bash
make verify-gate
```

**Default (E2E with DB):**
```bash
make verify-pipeline
```

**Comprehensive:**
```bash
make verify-all
```

**Specific Component:**
```bash
make verify-analysis
# or
make verify-auth
```

**Smoke tests:**
```bash
make smoke-api
make smoke-e2e
```

### 4. Report Results

**Success:**
```
✅ Verification Passed!
   - Pipeline: OK
   - Analysis: OK
```

**Failure:**
```
❌ Verification Failed:
   - Pipeline: DB Connection Error

   Tip: Check your Railway Shell connection or .env variables.
```

## Troubleshooting

| Error Message | Cause | Fix |
|--------------|-------|-----|
| `uismoke not found` | Missing test dependencies | `poetry install` |
| `TEST_AUTH_BYPASS_SECRET not found` | Running outside Railway context | `railway shell` or set env var |
| `Connection refused localhost:8000` | Dev server not running | `make dev` |
| `RAILWAY_SERVICE_FRONTEND_URL empty` | Missing Railway service URL | `railway shell` (env only available in Railway) |
| `psycopg2.OperationalError` | DB not accessible | Check Railway DB status: `railway status` |
| `ModuleNotFoundError: app` | Wrong working directory | Run from project root |
| `poetry.lock out of sync` | Lockfile drift | `poetry lock --no-update` |
| `EADDRINUSE: address already in use` | Port conflict | Kill process: `lsof -ti:8000 | xargs kill` |
| `FATAL: password authentication failed` | Invalid DB credentials | Check `DATABASE_URL` in Railway env |
| `Task timed out after 30s` | Slow network or cold start | Retry or use `--timeout 60` |

### Common Scenarios

**Scenario: "Works locally but fails in Railway Shell"**

1. Check environment parity:
   ```bash
   railway run env | grep -E "(DATABASE_URL|SECRET_KEY)"
   ```
2. Compare with local `.env`
3. Ensure all required vars are set in Railway

**Scenario: "Smoke tests pass but verify-pipeline fails"**

1. Smoke tests don't require DB; pipeline does
2. Check DB connection: `railway run python -c "from app.db import engine; print(engine.url)"` 3. Verify DB migrations: `railway run alembic current`

**Scenario: "Intermittent failures in CI"**

1. Check for race conditions in tests
2. Increase timeouts for cold starts
3. Add retry logic for flaky external services

## Best Practices

- **Always run from root** (where Makefile is).
- **Prefer `make` targets** over direct python scripts (`python scripts/...`).
- **Read output carefully** to catch specific failures (DB vs Logic).
- **Run verify-dev before every commit** to catch issues early.
- **Run verify-gate before every PR** to ensure CI will pass.

## Related Skills

- **lint-check**: Run before verification to catch syntax errors.
- **sync-feature-branch**: Run verification before syncing/committing.
- **railway-doctor**: Pre-flight checks for Railway deployments.
- **lockfile-doctor**: Check for lockfile drift before running tests.
