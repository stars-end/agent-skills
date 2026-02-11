---
name: railway-doctor
description: |
  Pre-flight checks for Railway deployments to catch failures BEFORE deploying.
  Use when about to deploy, running verify-* commands, or debugging Railway issues.
tags: [railway, deployment, validation, pre-flight]
allowed-tools:
  - Bash
---

# Railway Doctor

Pre-flight checks for Railway deployments and verify-* commands. Catches common configuration issues before they cause deployment failures.

## Pre-flight Checks

Run these checks BEFORE deploying or running verify-* commands (like `verify-pipeline`, `verify-deployment`, etc.) to catch issues early.

### 1. Railway Context Check

Verify Railway CLI is authenticated and has an active context:

```bash
# Check for Railway environment or token
if [[ -z "${RAILWAY_ENVIRONMENT:-}" && -z "${RAILWAY_TOKEN:-}" ]]; then
  echo "ERROR: No Railway context found."
  echo "  Set RAILWAY_ENVIRONMENT or RAILWAY_TOKEN, or run: railway login"
  exit 1
fi

# Verify CLI can connect
railway status 2>/dev/null || {
  echo "WARNING: Railway CLI not connected. Run: railway login"
}
```

**What it checks:**
- `RAILWAY_ENVIRONMENT` - Environment variable set by Railway
- `RAILWAY_TOKEN` - API token for Railway CLI authentication

**Quick Fix:**
```bash
railway login
# Or for CI/automation, set RAILWAY_TOKEN from 1Password:
export RAILWAY_TOKEN=$(op read "op://dx-secrets/railway-token/token" --account dx.1password.com)
```

### 2. URL Variables Check

Verify required service URL variables are configured:

```bash
# Check for service URL variables
MISSING_URLS=()

[[ -z "${RAILWAY_SERVICE_FRONTEND_URL:-}" ]] && MISSING_URLS+=("RAILWAY_SERVICE_FRONTEND_URL")
[[ -z "${RAILWAY_SERVICE_BACKEND_URL:-}" ]] && MISSING_URLS+=("RAILWAY_SERVICE_BACKEND_URL")

if [[ ${#MISSING_URLS[@]} -gt 0 ]]; then
  echo "ERROR: Missing service URL variables: ${MISSING_URLS[*]}"
  echo "  These are required for verify-* commands to work."
  echo ""
  echo "Quick Fix:"
  echo "  railway shell --command 'env | grep RAILWAY_SERVICE'"
  exit 1
fi
```

**What it checks:**
- `RAILWAY_SERVICE_FRONTEND_URL` - Frontend service public URL
- `RAILWAY_SERVICE_BACKEND_URL` - Backend service public URL

**Quick Fix:**
```bash
# Check what URL variables are available
railway shell

# Or set manually from Railway dashboard:
# Project > Service > Settings > Domains > Copy URL
railway variables set RAILWAY_SERVICE_FRONTEND_URL="https://your-app.up.railway.app"
railway variables set RAILWAY_SERVICE_BACKEND_URL="https://your-api.up.railway.app"
```

### 3. Auth Secret Check

Verify test authentication bypass secret is configured (for E2E tests):

```bash
# Check for auth bypass secret
if [[ -z "${TEST_AUTH_BYPASS_SECRET:-}" ]]; then
  echo "WARNING: TEST_AUTH_BYPASS_SECRET not set."
  echo "  E2E tests requiring auth bypass may fail."
  echo ""
  echo "Quick Fix:"
  echo "  railway variables set TEST_AUTH_BYPASS_SECRET='<from-1password>'"
fi
```

**What it checks:**
- `TEST_AUTH_BYPASS_SECRET` - Secret for bypassing auth in E2E/integration tests

**Quick Fix:**
```bash
# Set from 1Password
export TEST_AUTH_BYPASS_SECRET=$(op read "op://dx-secrets/test-auth-bypass/secret" --account dx.1password.com)

# Or set in Railway
railway variables set TEST_AUTH_BYPASS_SECRET="$(op read 'op://dx-secrets/test-auth-bypass/secret')"
```

## Quick Fix Reference

All pre-flight failures can be diagnosed/fixed via Railway shell:

```bash
# Open interactive Railway shell
railway shell

# Inside shell, check environment
env | grep RAILWAY
env | grep TEST_AUTH

# Set missing variables
variable set KEY=value
```

## Full Pre-flight Command

Run all checks at once:

```bash
#!/bin/bash
# railway-preflight.sh

ERRORS=0

# 1. Railway Context
if [[ -z "${RAILWAY_ENVIRONMENT:-}" && -z "${RAILWAY_TOKEN:-}" ]]; then
  echo "[FAIL] No Railway context (RAILWAY_ENVIRONMENT or RAILWAY_TOKEN)"
  ERRORS=$((ERRORS + 1))
else
  echo "[OK] Railway context found"
fi

# 2. URL Variables
[[ -n "${RAILWAY_SERVICE_FRONTEND_URL:-}" ]] && echo "[OK] RAILWAY_SERVICE_FRONTEND_URL set" || { echo "[FAIL] Missing RAILWAY_SERVICE_FRONTEND_URL"; ERRORS=$((ERRORS + 1)); }
[[ -n "${RAILWAY_SERVICE_BACKEND_URL:-}" ]] && echo "[OK] RAILWAY_SERVICE_BACKEND_URL set" || { echo "[FAIL] Missing RAILWAY_SERVICE_BACKEND_URL"; ERRORS=$((ERRORS + 1)); }

# 3. Auth Secret
[[ -n "${TEST_AUTH_BYPASS_SECRET:-}" ]] && echo "[OK] TEST_AUTH_BYPASS_SECRET set" || { echo "[WARN] TEST_AUTH_BYPASS_SECRET not set (E2E tests may fail)"; }

# Summary
echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "Pre-flight FAILED with $ERRORS error(s)"
  echo "Run 'railway shell' to diagnose and fix"
  exit 1
else
  echo "Pre-flight PASSED - ready to deploy"
fi
```

## When to Use

- **Before deploying**: Run pre-flight to catch config issues
- **Before verify-* commands**: Ensure URL variables and secrets are set
- **CI/CD pipelines**: Add as a pre-deploy step
- **Debugging failures**: Check environment when deploys fail
