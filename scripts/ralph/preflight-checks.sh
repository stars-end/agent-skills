#!/bin/bash
# Ralph Pre-flight Checks
# Validates environment before starting Ralph autonomous loop
# Exit codes: 0 (pass with warnings), 1 (errors), 2 (fatal)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

WARNINGS=0
ERRORS=0
FATAL=0

log_warn() {
    echo -e "${YELLOW}⚠️  WARNING: $*${NC}"
    ((WARNINGS++))
}

log_error() {
    echo -e "${RED}❌ ERROR: $*${NC}"
    ((ERRORS++))
}

log_fatal() {
    echo -e "${RED}🔴 FATAL: $*${NC}"
    ((FATAL++))
}

log_pass() {
    echo -e "${GREEN}✅ PASS: $*${NC}"
}

echo "=== Ralph Pre-flight Checks ==="
echo ""

# 1. Check git repo state
echo "[1/6] Git repository state..."
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_fatal "Not in a git repository"
else
    # Check if working directory is clean
    if [ -n "$(git status --porcelain)" ]; then
        log_warn "Working directory has uncommitted changes"
        git status --short
    else
        log_pass "Working directory clean"
    fi

    # Check if on a branch
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [ "$BRANCH" = "HEAD" ]; then
        log_warn "Not on a branch (detached HEAD)"
    else
        log_pass "On branch: $BRANCH"
    fi
fi
echo ""

# 2. Check RALPH_TASK.md exists
echo "[2/6] RALPH_TASK.md..."
if [ -f "RALPH_TASK.md" ]; then
    log_pass "RALPH_TASK.md exists"
    # Check if file has content
    if [ ! -s "RALPH_TASK.md" ]; then
        log_warn "RALPH_TASK.md is empty"
    fi
else
    log_error "RALPH_TASK.md not found"
fi
echo ""

# 3. Check OpenCode agents configuration
echo "[3/6] OpenCode agents..."
OPENCODE_AGENTS="$HOME/.opencode/agents"
if [ ! -d "$OPENCODE_AGENTS" ]; then
    log_error "OpenCode agents directory not found: $OPENCODE_AGENTS"
else
    # Check for required agents
    REQUIRED_AGENTS=("ralph-implementer" "ralph-reviewer")
    for agent in "${REQUIRED_AGENTS[@]}"; do
        if [ -f "$OPENCODE_AGENTS/$agent.json" ]; then
            # Validate JSON
            if jq empty "$OPENCODE_AGENTS/$agent.json" 2>/dev/null; then
                log_pass "Agent $agent configured"
            else
                log_error "Agent $agent has invalid JSON"
            fi
        else
            log_error "Agent not configured: $agent"
        fi
    done
fi
echo ""

# 4. Check OpenCode CLI/server
echo "[4/6] OpenCode server..."
BASE="http://127.0.0.1:4105"
if curl -s "$BASE/global/health" >/dev/null 2>&1; then
    VERSION=$(curl -s "$BASE/global/health" | jq -r '.version // "unknown"' 2>/dev/null)
    log_pass "OpenCode server running (version: $VERSION)"
else
    log_fatal "OpenCode server not responding at $BASE"
fi
echo ""

# 5. Check required commands
echo "[5/6] Required commands..."
REQUIRED_COMMANDS=("jq" "curl" "bd" "git")
MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_pass "$cmd available"
    else
        log_error "$cmd not found"
        MISSING_COMMANDS+=("$cmd")
    fi
done
echo ""

# 6. Check disk space
echo "[6/6] Disk space..."
AVAILABLE=$(df . | tail -1 | awk '{print $4}')
AVAILABLE_MB=$((AVAILABLE / 1024))
if [ "$AVAILABLE_MB" -lt 100 ]; then
    log_fatal "Low disk space: ${AVAILABLE_MB}MB available (< 100MB)"
elif [ "$AVAILABLE_MB" -lt 500 ]; then
    log_warn "Low disk space: ${AVAILABLE_MB}MB available (< 500MB)"
else
    log_pass "Disk space OK: ${AVAILABLE_MB}MB available"
fi
echo ""

# Summary
echo "=== Summary ==="
echo "Warnings: $WARNINGS"
echo "Errors: $ERRORS"
echo "Fatal: $FATAL"
echo ""

if [ $FATAL -gt 0 ]; then
    echo -e "${RED}🔴 PREFLIGHT FAILED (FATAL)${NC}"
    exit 2
elif [ $ERRORS -gt 0 ]; then
    echo -e "${RED}❌ PREFLIGHT FAILED (ERRORS)${NC}"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PREFLIGHT PASSED WITH WARNINGS${NC}"
    exit 0
else
    echo -e "${GREEN}✅ ALL PREFLIGHT CHECKS PASSED${NC}"
    exit 0
fi
