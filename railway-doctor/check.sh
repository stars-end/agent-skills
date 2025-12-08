#!/bin/bash
# railway-doctor check - Pre-flight checks for Railway deployments

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
    poetry install --no-root --quiet
  fi

  # Test critical imports
  if poetry run python -c "
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd()))

# Test critical imports that commonly break in Railway
try:
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
  echo "ℹ️  No railway.toml or railway.json found"
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
  echo "Or run: ~/.agent/skills/railway-doctor/fix.sh"
  exit 1
fi
