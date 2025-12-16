# Railway Preflight Composite Action

Pre-deployment validation for Railway: catch deployment failures before they happen.

## Features

- ✅ **Lockfile validation**: Ensure Poetry lockfile in sync (prevents Railway build failures)
- ✅ **Import validation**: Test critical Python imports work
- ✅ **Environment validation**: Check required env vars are set
- ✅ **Fast feedback**: Fail in CI before deploying to Railway

## Usage

### Basic (Lockfiles Only)

```yaml
- uses: stars-end/agent-skills/.github/actions/railway-preflight@main
  with:
    backend-directory: backend/
```

### With Import Validation

```yaml
- uses: stars-end/agent-skills/.github/actions/railway-preflight@main
  with:
    backend-directory: backend/
    check-imports: true
```

### With Environment Variable Checks

```yaml
- uses: stars-end/agent-skills/.github/actions/railway-preflight@main
  with:
    backend-directory: backend/
    check-env-vars: true
    required-env-vars: 'DATABASE_URL,CLERK_SECRET_KEY,SUPABASE_URL'
```

### Full Preflight (All Checks)

```yaml
- uses: stars-end/agent-skills/.github/actions/railway-preflight@main
  with:
    backend-directory: backend/
    check-imports: true
    check-env-vars: true
    required-env-vars: 'DATABASE_URL,CLERK_SECRET_KEY,SUPABASE_URL,EODHD_API_KEY'
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `backend-directory` | Backend directory to validate | No | `backend` |
| `check-imports` | Validate critical Python imports | No | `true` |
| `check-env-vars` | Check for required env vars | No | `false` |
| `required-env-vars` | Comma-separated env var list | No | `''` |

## Outputs

| Output | Description | Values |
|--------|-------------|--------|
| `lockfile-status` | Lockfile validation status | `ok`, `drift`, `missing` |
| `imports-status` | Import validation status | `ok`, `error`, `skipped` |
| `env-status` | Environment validation status | `ok`, `missing`, `skipped` |

## What It Checks

### 1. Lockfile Sync (Always)
**Validates**: `poetry check --lock`
**Prevents**: Railway build failures due to lockfile drift
**Fix**: `poetry lock --no-update`

### 2. Critical Imports (Optional)
**Validates**: `import fastapi; import sqlalchemy; import pydantic`
**Prevents**: Runtime import errors in Railway
**Fix**: Check dependency versions in pyproject.toml

### 3. Environment Variables (Optional)
**Validates**: Required env vars are set in CI
**Prevents**: Railway runtime failures due to missing config
**Fix**: Set vars in Railway dashboard or GitHub secrets

## Integration Example

```yaml
name: Railway Deploy

on:
  push:
    branches: [master]

jobs:
  preflight:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Poetry
        run: pip install poetry

      - uses: stars-end/agent-skills/.github/actions/python-setup@main
        with:
          working-directory: backend/

      - uses: stars-end/agent-skills/.github/actions/railway-preflight@main
        with:
          backend-directory: backend/
          check-imports: true
          check-env-vars: true
          required-env-vars: 'DATABASE_URL,CLERK_SECRET_KEY'
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
          CLERK_SECRET_KEY: ${{ secrets.CLERK_SECRET_KEY }}

  deploy:
    needs: preflight
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Deploy to Railway
        uses: bervProject/railway-deploy@main
        with:
          railway_token: ${{ secrets.RAILWAY_TOKEN }}
          service: backend
```

## What It Prevents

**Pattern 2: Railway Deployment Failures** (12/69 toil commits eliminated)
- ❌ Before: Deploy → Build fails → Check logs → Fix lockfile → Redeploy (10-15 min)
- ✅ After: CI catches issues in 2-3 min with clear fix instructions

**Common Railway failures prevented**:
1. Lockfile drift → `poetry install` fails in Railway build
2. Missing dependencies → Import errors at runtime
3. Missing env vars → Application crashes on startup

## Local Alternative

For local pre-flight checks:
```bash
~/.agent/skills/railway-doctor/check.sh
~/.agent/skills/railway-doctor/fix.sh
```

## Troubleshooting

### Lockfile check fails but `poetry check --lock` passes locally

Ensure using same Poetry version:
```yaml
- name: Install specific Poetry version
  run: pip install poetry==1.7.1  # Match your local version
```

### Import check fails in CI but works locally

Check Python version mismatch:
```yaml
- uses: stars-end/agent-skills/.github/actions/python-setup@main
  # Auto-detects from pyproject.toml - ensures CI matches local
```

### Env var check fails

Set secrets in GitHub:
1. Go to repo Settings → Secrets and variables → Actions
2. Add required secrets (DATABASE_URL, etc.)
3. Reference in workflow: `env: { DATABASE_URL: ${{ secrets.DATABASE_URL }} }`

## Railway-Specific Notes

Railway deployments fail when:
- `poetry.lock` out of sync → Build stage fails
- Missing dependencies → Runtime import errors
- Missing env vars → Application startup crashes

This action catches all three before deployment, saving 10-15 min per failure.

## Related

- **python-setup action**: Sets up Poetry environment
- **lockfile-check action**: Similar but without Railway-specific checks
- **railway-doctor skill**: Local equivalent with auto-fix
