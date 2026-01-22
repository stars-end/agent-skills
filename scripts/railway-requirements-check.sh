#!/usr/bin/env bash
# railway-requirements-check.sh - Railway Requirements Verification
#
# Checks Railway access requirements based on ENV_SOURCES_MODE
# Hard-fails when RAILWAY_TOKEN required but missing, warns otherwise
#
# Usage:
#   ./railway-requirements-check.sh [--mode MODE]
#   ./railway-requirements-check.sh --self-test
#
# Modes:
#   local-dev    : Railway optional (local development)
#   interactive  : Railway optional (manual workflows)
#   automated    : Railway required (CI/CD, scripts)
#   ci           : Railway required (CI pipelines)
#
# ENV_SOURCES_MODE: Environment variable to set default mode
#
# Examples:
#   # Check with explicit mode
#   ./railway-requirements-check.sh --mode automated
#
#   # Check with ENV_SOURCES_MODE
#   export ENV_SOURCES_MODE=ci
#   ./railway-requirements-check.sh
#
#   # Self-test all modes
#   ./railway-requirements-check.sh --self-test

set -euo pipefail

# Default mode from environment or auto-detect
DEFAULT_MODE="${ENV_SOURCES_MODE:-auto}"

# Parse arguments
MODE=""
SELF_TEST=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --self-test)
            SELF_TEST=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--mode MODE] [--self-test]"
            echo ""
            echo "Modes:"
            echo "  local-dev    Railway optional (local development)"
            echo "  interactive  Railway optional (manual workflows)"
            echo "  automated    Railway required (CI/CD, scripts)"
            echo "  ci           Railway required (CI pipelines)"
            echo "  auto         Auto-detect from environment (default)"
            echo ""
            echo "Environment:"
            echo "  ENV_SOURCES_MODE  Set default mode"
            echo "  RAILWAY_TOKEN     Railway API token (required for automated/ci)"
            echo ""
            echo "Self-Test:"
            echo "  --self-test  Test all modes and verify behavior"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Use --help for usage" >&2
            exit 1
            ;;
    esac
done

# Self-test mode
if [[ "$SELF_TEST" == "true" ]]; then
    echo "=== Railway Requirements Self-Test ==="
    echo ""

    # Save current token state
    CURRENT_TOKEN="${RAILWAY_TOKEN:-}"
    export RAILWAY_TOKEN=""

    echo "Test 1: local-dev mode (no token) - should PASS (optional)"
    ENV_SOURCES_MODE=local-dev "$0" --mode local-dev && echo "✅ PASS" || echo "❌ FAIL"
    echo ""

    echo "Test 2: interactive mode (no token) - should PASS (optional)"
    ENV_SOURCES_MODE=interactive "$0" --mode interactive && echo "✅ PASS" || echo "❌ FAIL"
    echo ""

    echo "Test 3: automated mode (no token) - should FAIL (required)"
    ENV_SOURCES_MODE=automated "$0" --mode automated 2>&1 | head -3 && echo "❌ Should have failed" || echo "✅ PASS (correctly failed)"
    echo ""

    echo "Test 4: automated mode (with token) - should PASS"
    export RAILWAY_TOKEN="test_token_12345"
    ENV_SOURCES_MODE=automated "$0" --mode automated && echo "✅ PASS" || echo "❌ FAIL"
    echo ""

    # Restore token
    if [[ -n "$CURRENT_TOKEN" ]]; then
        export RAILWAY_TOKEN="$CURRENT_TOKEN"
    else
        unset RAILWAY_TOKEN
    fi

    echo "=== Self-Test Complete ==="
    exit 0
fi

# Determine mode
if [[ -z "$MODE" ]]; then
    MODE="$DEFAULT_MODE"
fi

# Auto-detect mode
if [[ "$MODE" == "auto" ]]; then
    # Check if we're in CI
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${RAILWAY_CI:-}" ]]; then
        MODE="ci"
    # Check if we're being run non-interactively
    elif [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
        MODE="automated"
    else
        MODE="local-dev"
    fi
fi

echo "=== Railway Requirements Check ==="
echo "Mode: $MODE"
echo ""

# Check Railway CLI availability
RAILWAY_CLI=""
if command -v railway >/dev/null 2>&1; then
    RAILWAY_CLI="$(command -v railway)"
    RAILWAY_VERSION="$(railway --version 2>/dev/null || echo "unknown")"
    echo "✅ Railway CLI found: $RAILWAY_CLI ($RAILWAY_VERSION)"
else
    echo "⚠️  Railway CLI not found"
    echo "   Install: mise use -g railway@latest"
fi
echo ""

# Check Railway authentication
RAILWAY_AUTH_STATUS="unknown"
if command -v railway >/dev/null 2>&1; then
    if railway status >/dev/null 2>&1; then
        RAILWAY_AUTH_STATUS="authenticated"
        echo "✅ Railway CLI: Authenticated (interactive session)"
    else
        RAILWAY_AUTH_STATUS="not_authenticated"
        echo "⚠️  Railway CLI: Not authenticated"
        echo "   Run: railway login"
    fi
else
    echo "⚠️  Railway CLI: Not installed"
fi
echo ""

# Check RAILWAY_TOKEN
RAILWAY_TOKEN_SET=false
if [[ -n "${RAILWAY_TOKEN:-}" ]]; then
    RAILWAY_TOKEN_SET=true
    TOKEN_MASKED="${RAILWAY_TOKEN:0:8}...${RAILWAY_TOKEN: -8}"
    echo "✅ RAILWAY_TOKEN: Set ($TOKEN_MASKED)"
else
    echo "⚠️  RAILWAY_TOKEN: Not set"
    echo "   Load from 1Password:"
    echo "   export RAILWAY_TOKEN=\$(op item get --vault dev Railway-Delivery --fields label=token)"
fi
echo ""

# Determine if Railway is required
RAILWAY_REQUIRED=false
case "$MODE" in
    local-dev|interactive)
        RAILWAY_REQUIRED=false
        echo "ℹ️  Mode '$MODE': Railway access is OPTIONAL"
        ;;
    automated|ci)
        RAILWAY_REQUIRED=true
        echo "ℹ️  Mode '$MODE': Railway access is REQUIRED"
        ;;
    *)
        echo "❌ ERROR: Unknown mode: $MODE" >&2
        echo "Valid modes: local-dev, interactive, automated, ci" >&2
        exit 1
        ;;
esac
echo ""

# Final check
if [[ "$RAILWAY_REQUIRED" == "true" ]]; then
    if [[ "$RAILWAY_TOKEN_SET" == "true" ]]; then
        echo "✅ PASS: Railway token is set (required for '$MODE' mode)"
        exit 0
    else
        echo "❌ FAIL: RAILWAY_TOKEN must be set for '$MODE' mode" >&2
        echo "" >&2
        echo "Required actions:" >&2
        echo "  1. Load token from 1Password:" >&2
        echo "     export RAILWAY_TOKEN=\$(op item get --vault dev Railway-Delivery --fields label=token)" >&2
        echo "  2. Or use interactive mode: railway login" >&2
        echo "  3. Or use local-dev mode (if Railway not needed)" >&2
        exit 1
    fi
else
    if [[ "$RAILWAY_AUTH_STATUS" == "authenticated" ]] || [[ "$RAILWAY_TOKEN_SET" == "true" ]]; then
        echo "✅ PASS: Railway access available (optional for '$MODE' mode)"
    else
        echo "✅ PASS: Railway access not required for '$MODE' mode"
    fi
    exit 0
fi
