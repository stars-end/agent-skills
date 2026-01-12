#!/bin/bash
# railway-common.sh - Shared utilities for Railway skills integration
#
# Part of the agent-skills registry
# Compatible with: Claude Code, Codex CLI, OpenCode, Gemini CLI, Antigravity
#
# Usage:
#   source ~/.agent/skills/lib/railway-common.sh
#   railway_check_auth
#   railway_check_cli_version

set -euo pipefail

# Minimum Railway CLI version for GraphQL API support
RAILWAY_MIN_VERSION="3.0.0"

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Get Railway CLI version
railway_get_version() {
    if command -v railway &>/dev/null; then
        railway --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0"
    else
        echo "0.0.0"
    fi
}

# Compare versions (returns: 0=equal, 1=first>second, -1=first<second)
version_compare() {
    if [[ "$1" == "$2" ]]; then
        echo "0"
        return
    fi

    local IFS=.
    local i ver1=($1) ver2=($2)

    # Fill empty fields with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++)); do
        ver1[i]=0
    done

    for ((i=0; i<${#ver1[@]}; i++)); do
        if [[ -z ${ver2[i]} ]]; then
            ver2[i]=0
        fi

        if ((10#${ver1[i]} > 10#${ver2[i]})); then
            echo "1"
            return
        fi

        if ((10#${ver1[i]} < 10#${ver2[i]})); then
            echo "-1"
            return
        fi
    done

    echo "0"
}

# Check Railway CLI version
railway_check_cli_version() {
    local version
    version=$(railway_get_version)

    if [[ "$version" == "0.0.0" ]]; then
        log_error "Railway CLI not found"
        echo "  Install: mise use -g railway@latest"
        echo "  Or: npm install -g @railway/cli"
        return 1
    fi

    local comparison
    comparison=$(version_compare "$version" "$RAILWAY_MIN_VERSION")

    if [[ "$comparison" -lt 0 ]]; then
        log_warn "Railway CLI version $version < $RAILWAY_MIN_VERSION"
        echo "  Update: mise use -g railway@latest"
        echo "  GraphQL API features require version >= $RAILWAY_MIN_VERSION"
        return 1
    fi

    log_info "Railway CLI version $version (>= $RAILWAY_MIN_VERSION)"
    return 0
}

# Check Railway authentication
railway_check_auth() {
    if ! command -v railway &>/dev/null; then
        log_error "Railway CLI not found"
        return 1
    fi

    if ! railway status &>/dev/null; then
        log_warn "Railway not authenticated"
        echo "  Run: railway login"
        return 1
    fi

    log_info "Railway authenticated"
    return 0
}

# Detect monorepo type
railway_detect_monorepo() {
    local has_root_dir=false
    local is_shared_monorepo=false

    # Check for rootDirectory in railway.toml
    if [[ -f "railway.toml" ]] && grep -q "rootDirectory" railway.toml; then
        has_root_dir=true
    fi

    # Check for shared monorepo indicators
    if [[ -f "pnpm-workspace.yaml" ]] || \
       grep -q '"workspaces"' package.json 2>/dev/null || \
       [[ -f "turbo.json" ]] || \
       [[ -f "nx.json" ]]; then
        is_shared_monorepo=true
    fi

    # Check for Python monorepo with relative imports
    if [[ -f "pyproject.toml" ]] && grep -q '\.\./' pyproject.toml 2>/dev/null; then
        is_shared_monorepo=true
    fi

    if [[ "$has_root_dir" == "true" ]] && [[ "$is_shared_monorepo" == "true" ]]; then
        echo "isolated-with-shared"  # Invalid configuration
    elif [[ "$has_root_dir" == "true" ]]; then
        echo "isolated"
    elif [[ "$is_shared_monorepo" == "true" ]]; then
        echo "shared"
    else
        echo "single"
    fi
}

# Get skills plane library path (works for both agent types)
railway_get_lib_path() {
    local lib_path
    lib_path="${CLAUDE_PLUGIN_ROOT:-$HOME/.agent/skills}/lib"

    if [[ ! -d "$lib_path" ]]; then
        echo ""
        return 1
    fi

    echo "$lib_path"
    return 0
}

# Check if Railway API script exists
railway_check_api_script() {
    local lib_path
    lib_path=$(railway_get_lib_path)

    if [[ -z "$lib_path" ]]; then
        log_error "Skills plane lib directory not found"
        echo "  Run: ~/agent-skills/scripts/ensure_agent_skills_mount.sh"
        return 1
    fi

    if [[ ! -f "$lib_path/railway-api.sh" ]]; then
        log_warn "Railway API script not found"
        echo "  Expected: $lib_path/railway-api.sh"
        echo "  Install from: https://github.com/railwayapp/railway-skills"
        return 1
    fi

    log_info "Railway API script found: $lib_path/railway-api.sh"
    return 0
}

# Main validation function
railway_validate_environment() {
    local errors=0

    echo "🚂 Railway Environment Validation"
    echo ""

    # Check CLI version
    if ! railway_check_cli_version; then
        errors=$((errors + 1))
    fi

    echo ""

    # Check authentication
    if ! railway_check_auth; then
        errors=$((errors + 1))
    fi

    echo ""

    # Check API script
    if ! railway_check_api_script; then
        errors=$((errors + 1))
    fi

    echo ""
    echo "═══════════════════════════════════════"

    if [[ $errors -eq 0 ]]; then
        log_info "All Railway checks passed!"
        return 0
    else
        log_error "Found $errors issue(s)"
        return 1
    fi
}

# Export functions for use in other scripts
export -f log_info log_warn log_error
export -f railway_get_version
export -f version_compare
export -f railway_check_cli_version
export -f railway_check_auth
export -f railway_detect_monorepo
export -f railway_get_lib_path
export -f railway_check_api_script
export -f railway_validate_environment
