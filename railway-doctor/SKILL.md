# railway-doctor

## Description

Pre-flight checks for Railway deployments to catch failures BEFORE deploying.

**Use when**:
- About to deploy to Railway ("deploy to railway", "railway up")
- Railway deployment fails (imports break, env issues, lockfile errors)
- Debugging Railway 500 errors
- User says "check railway", "railway pre-flight", "why did railway fail"

**Problem solved**: Eliminates "Deploy to Railway → Imports break → Iterate" pattern (12/69 toil commits, 17% of analyzed toil).

## Auto-Activation

This skill activates when:
- User mentions Railway deployment ("railway", "deploy", "railway up")
- CI deployment step fails
- Railway shows 500 errors or build failures
- Before important deployments (staging, production)

## Implementation

The skill performs comprehensive pre-flight checks to catch Railway deployment issues early.

### Check Script

```bash
#!/bin/bash
# ~/.agent/skills/railway-doctor/check.sh

set -e

echo "🚂 Railway Doctor - Pre-flight Check"

ISSUES_FOUND=0

# Check 1: Critical Python imports (Backend)
if [[ -f "backend/pyproject.toml" ]]; then
  echo ""
  echo "🐍 Checking Python imports (backend)..."
  cd backend

  # Ensure poetry env exists
  if ! poetry env info &>/dev/null; then
    echo "Installing Poetry environment..."
    poetry install --no-root
  fi

  # Test critical imports
  if poetry run python -c "
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))

# Test critical imports that commonly break in Railway
try:
    from services.plaid_adapter import PlaidAdapter
    from brokers.security_resolver import SecurityResolver
    from api.routers import health
    print('✅ All critical imports valid')
except ImportError as e:
    print(f'❌ Import will fail in Railway: {e}')
    sys.exit(1)
" 2>&1; then
    echo "✅ Backend imports validated"
  else
    echo "❌ ERROR: Backend imports will fail in Railway"
    echo "   Fix import paths or missing dependencies"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi

  cd ..
fi

# Check 2: Lockfiles in sync
echo ""
echo "📦 Checking lockfiles..."

# Poetry lockfile
if [[ -f "backend/pyproject.toml" ]]; then
  cd backend
  if poetry check --lock 2>/dev/null; then
    echo "✅ backend/poetry.lock in sync"
  else
    echo "❌ ERROR: backend/poetry.lock out of sync"
    echo "   Run: cd backend && poetry lock --no-update"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  cd ..
elif [[ -f "pyproject.toml" ]]; then
  if poetry check --lock 2>/dev/null; then
    echo "✅ poetry.lock in sync"
  else
    echo "❌ ERROR: poetry.lock out of sync"
    echo "   Run: poetry lock --no-update"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
fi

# pnpm lockfile
if [[ -f "frontend/package.json" ]]; then
  cd frontend
  if pnpm install --frozen-lockfile 2>/dev/null; then
    echo "✅ frontend/pnpm-lock.yaml in sync"
  else
    echo "❌ ERROR: frontend/pnpm-lock.yaml out of sync"
    echo "   Run: cd frontend && pnpm install"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
  cd ..
elif [[ -f "package.json" ]]; then
  if pnpm install --frozen-lockfile 2>/dev/null; then
    echo "✅ pnpm-lock.yaml in sync"
  else
    echo "❌ ERROR: pnpm-lock.yaml out of sync"
    echo "   Run: pnpm install"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  fi
fi

# Check 3: Required environment variables (if Railway CLI available)
if command -v railway &>/dev/null; then
  echo ""
  echo "🔑 Checking Railway environment variables..."

  REQUIRED_VARS=(
    "DATABASE_URL"
    "SUPABASE_URL"
    "CLERK_SECRET_KEY"
  )

  for VAR in "${REQUIRED_VARS[@]}"; do
    if railway variables 2>/dev/null | grep -q "^$VAR"; then
      echo "✅ $VAR set"
    else
      echo "⚠️  WARNING: $VAR not set in Railway environment"
      echo "   Set via: railway variables set $VAR=<value>"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
  done
else
  echo ""
  echo "ℹ️  Railway CLI not installed (skipping env var check)"
  echo "   Install: npm install -g @railway/cli"
fi

# Check 4: Railway configuration file
echo ""
echo "⚙️  Checking Railway configuration..."

if [[ -f "railway.toml" ]] || [[ -f "railway.json" ]]; then
  echo "✅ Railway config file found"
else
  echo "⚠️  No railway.toml or railway.json found"
  echo "   Consider adding for build configuration"
fi

echo ""
echo "═══════════════════════════════════════"
if [[ $ISSUES_FOUND -eq 0 ]]; then
  echo "✅ All pre-flight checks passed!"
  echo "   Safe to deploy to Railway"
  exit 0
else
  echo "❌ Found $ISSUES_FOUND issue(s) - deployment will likely fail"
  echo ""
  echo "Fix issues before deploying to Railway"
  exit 1
fi
```

### Fix Script

```bash
#!/bin/bash
# ~/.agent/skills/railway-doctor/fix.sh

set -e

echo "🔧 Railway Doctor - Fixing issues..."

FIXED=0

# Fix 1: Regenerate lockfiles
echo ""
echo "📦 Fixing lockfiles..."

# Poetry
if [[ -f "backend/pyproject.toml" ]]; then
  cd backend
  if ! poetry check --lock 2>/dev/null; then
    echo "Regenerating backend/poetry.lock..."
    poetry lock --no-update
    git add poetry.lock
    echo "✅ backend/poetry.lock fixed"
    FIXED=$((FIXED + 1))
  fi
  cd ..
elif [[ -f "pyproject.toml" ]]; then
  if ! poetry check --lock 2>/dev/null; then
    echo "Regenerating poetry.lock..."
    poetry lock --no-update
    git add poetry.lock
    echo "✅ poetry.lock fixed"
    FIXED=$((FIXED + 1))
  fi
fi

# pnpm
if [[ -f "frontend/package.json" ]]; then
  cd frontend
  if ! pnpm install --frozen-lockfile 2>/dev/null; then
    echo "Regenerating frontend/pnpm-lock.yaml..."
    pnpm install
    git add pnpm-lock.yaml
    echo "✅ frontend/pnpm-lock.yaml fixed"
    FIXED=$((FIXED + 1))
  fi
  cd ..
elif [[ -f "package.json" ]]; then
  if ! pnpm install --frozen-lockfile 2>/dev/null; then
    echo "Regenerating pnpm-lock.yaml..."
    pnpm install
    git add pnpm-lock.yaml
    echo "✅ pnpm-lock.yaml fixed"
    FIXED=$((FIXED + 1))
  fi
fi

# Fix 2: Import issues - can't auto-fix, only provide guidance
if [[ -f "backend/pyproject.toml" ]]; then
  cd backend
  if ! poetry run python -c "
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))
from services.plaid_adapter import PlaidAdapter
" 2>/dev/null; then
    echo ""
    echo "⚠️  Cannot auto-fix: Import errors detected"
    echo "   Manual fixes needed:"
    echo "   - Check import paths in Railway match local"
    echo "   - Verify all dependencies in pyproject.toml"
    echo "   - Test with: cd backend && poetry run python -c 'from services.plaid_adapter import PlaidAdapter'"
  fi
  cd ..
fi

# Fix 3: Environment variables - can't auto-fix, only guide
if command -v railway &>/dev/null; then
  echo ""
  echo "⚠️  Environment variable issues require manual setup in Railway dashboard"
  echo "   Or use: railway variables set VARIABLE_NAME=value"
fi

echo ""
echo "═══════════════════════════════════════"
if [[ $FIXED -eq 0 ]]; then
  echo "ℹ️  No auto-fixable issues found"
  echo "   Check error messages above for manual fixes"
else
  echo "✅ Fixed $FIXED issue(s)"
  echo ""
  echo "Re-run railway-doctor check to verify all issues resolved"
fi
```

## Usage Examples

### Pre-flight check before deployment
```bash
railway-doctor check
```

### Auto-fix lockfile issues
```bash
railway-doctor fix
```

### CI Integration
```yaml
# .github/workflows/deploy.yml
- name: Railway Pre-flight Check
  run: ~/.agent/skills/railway-doctor/check.sh

- name: Deploy to Railway
  if: success()
  run: railway up
```

### Agent workflow
```
1. User: "deploy to railway"
2. Agent: Run railway-doctor check
3. If passes: railway up
4. If fails: railway-doctor fix, then re-check
```

## Common Issues & Fixes

### Issue 1: Import errors in Railway
**Symptom**: Works locally, fails in Railway with `ModuleNotFoundError`
**Cause**: Import paths different in Railway vs local
**Check**: railway-doctor validates critical imports
**Fix**: Adjust sys.path or restructure imports

### Issue 2: Lockfile out of sync
**Symptom**: Railway build fails with "dependency mismatch"
**Cause**: pyproject.toml changed without poetry lock
**Check**: railway-doctor validates lockfiles
**Fix**: Auto-fixed with railway-doctor fix

### Issue 3: Missing environment variables
**Symptom**: Railway 500 errors, missing DATABASE_URL etc.
**Cause**: Env vars not set in Railway project
**Check**: railway-doctor checks required vars (if Railway CLI installed)
**Fix**: Manual setup via Railway dashboard or CLI

### Issue 4: Railpack version breaking changes
**Symptom**: Build works locally, fails in Railway after Railpack update
**Cause**: Railpack breaking change (e.g., 0.0.70 packageManager field)
**Prevention**: Pin Railpack version in railway.toml

## Cross-Repo Deployment

This skill deploys to `~/.agent/skills/` and works across:
- ✅ All repos (prime-radiant-ai, affordabot, any Railway project)
- ✅ All AI agents (Claude Code, Codex CLI, Antigravity)
- ✅ All VMs (shared via Universal Skills MCP)

## Success Metrics

**Baseline**: 12 commits (17% of toil) wasted on Railway deployment failures
**Target**: <2 commits per 60-commit cycle
**Impact**: ~2-3 hours/month saved, fewer deployment iterations

## Notes

**Design Philosophy**:
- Fail fast locally (before pushing to Railway)
- Validate critical imports (catches 80% of issues)
- Clear guidance for non-auto-fixable issues
- Agent-friendly (railway-doctor check → fix → deploy)

**Why not full Railway simulator?**
- Over-engineering: Pre-flight + better logging gets 80% value
- Complexity: Full simulator may still diverge from actual Railway
- ROI: 2-3 days vs 1 day for similar impact

**Complementary with**:
- Enhanced Railway logging (bd-vs87) - for debugging deployed errors
- lockfile-doctor skill (bd-heb9) - for dependency management
