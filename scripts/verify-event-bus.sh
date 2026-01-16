#!/bin/zsh
# Full Event Bus Integration Test
# Tests: dispatcher → Slack → controller → state file
#
# Usage: ./verify-event-bus.sh [--local | --remote]
#   --local: Run on local machine only
#   --remote: Also test on epyc6 and homedesktop-wsl

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "🔗 Agent Event Bus - Full Integration Test"
echo "========================================"
echo ""

# Parse args
RUN_REMOTE=false
if [[ "$1" == "--remote" ]]; then
    RUN_REMOTE=true
fi

# Track results
PASSED=0
FAILED=0

test_result() {
    if [[ $1 -eq 0 ]]; then
        echo -e "${GREEN}✅ PASSED${NC}: $2"
        ((PASSED++))
    else
        echo -e "${RED}❌ FAILED${NC}: $2"
        ((FAILED++))
    fi
}

# ============================================================
# Phase 1: Pre-flight Checks
# ============================================================
echo "📋 Phase 1: Pre-flight Checks"
echo "---"

# Check slack-mcp-server
SLACK_MCP="$HOME/go/bin/slack-mcp-server"
if [[ ! -f "$SLACK_MCP" ]]; then
    SLACK_MCP="/home/linuxbrew/.linuxbrew/bin/slack-mcp-server"
fi
if [[ -f "$SLACK_MCP" ]]; then
    test_result 0 "slack-mcp-server found at $SLACK_MCP"
else
    test_result 1 "slack-mcp-server not found"
    echo "Install with: go install github.com/korotovsky/slack-mcp-server/cmd/slack-mcp-server@latest"
    exit 1
fi

# Source .zshenv for Slack tokens
source ~/.zshenv 2>/dev/null || true

# Check env vars
if [[ -n "$SLACK_MCP_XOXB_TOKEN" ]] || [[ -n "$SLACK_MCP_XOXP_TOKEN" ]]; then
    test_result 0 "Slack MCP token configured"
else
    test_result 1 "No Slack MCP token found in environment"
    echo "Set SLACK_MCP_XOXB_TOKEN or SLACK_MCP_XOXP_TOKEN in ~/.zshenv"
    exit 1
fi

# ============================================================
# Phase 2: Clear State
# ============================================================
echo ""
echo "📋 Phase 2: Clear Controller State"
echo "---"

rm -rf ~/.fleet-controller
mkdir -p ~/.fleet-controller
test_result 0 "Controller state cleared"

# ============================================================
# Phase 3: Event Posting (E2E Test Script)
# ============================================================
echo ""
echo "📋 Phase 3: Event Posting"
echo "---"

cd "$REPO_ROOT"
source ~/.zshenv 2>/dev/null || true

E2E_OUTPUT=$(python3 scripts/test-event-bus-e2e.py 2>&1)
E2E_EXIT=$?

if [[ $E2E_EXIT -eq 0 ]] && echo "$E2E_OUTPUT" | grep -q "6 passed"; then
    test_result 0 "E2E test posted 6 events"
else
    test_result 1 "E2E test failed"
    echo "$E2E_OUTPUT" | tail -10
    exit 1
fi

# ============================================================
# Phase 4: Controller Processing
# ============================================================
echo ""
echo "📋 Phase 4: Controller Processing"
echo "---"

sleep 2  # Allow Slack to propagate

CTRL_OUTPUT=$(python3 -m lib.fleet.controller --once 2>&1)
CTRL_EXIT=$?

if [[ $CTRL_EXIT -eq 0 ]]; then
    test_result 0 "Controller ran successfully"
else
    test_result 1 "Controller failed"
    echo "$CTRL_OUTPUT" | tail -20
fi

# Check events parsed
PARSED_COUNT=$(echo "$CTRL_OUTPUT" | grep -c "Parsed as key:value" || echo 0)
if [[ $PARSED_COUNT -ge 3 ]]; then
    test_result 0 "Controller parsed $PARSED_COUNT events"
else
    test_result 1 "Controller parsed only $PARSED_COUNT events (expected >=3)"
fi

# ============================================================
# Phase 5: State File Verification
# ============================================================
echo ""
echo "📋 Phase 5: State File Verification"
echo "---"

if [[ -f ~/.fleet-controller/state.json ]]; then
    test_result 0 "state.json exists"
    CURSOR=$(cat ~/.fleet-controller/state.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('last_seen_ts', '0'))" 2>/dev/null)
    if [[ "$CURSOR" != "0" ]]; then
        test_result 0 "Cursor updated to $CURSOR"
    else
        test_result 1 "Cursor not updated"
    fi
else
    test_result 1 "state.json not created"
fi

if [[ -f ~/.fleet-controller/dispatches.json ]]; then
    DISPATCH_COUNT=$(cat ~/.fleet-controller/dispatches.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d))" 2>/dev/null)
    test_result 0 "dispatches.json has $DISPATCH_COUNT entries"
    
    # Check specific repos were tracked
    if cat ~/.fleet-controller/dispatches.json | grep -q "prime-radiant-ai"; then
        test_result 0 "prime-radiant-ai dispatch tracked"
    else
        test_result 1 "prime-radiant-ai dispatch not tracked"
    fi
else
    echo -e "${YELLOW}⚠️  WARNING${NC}: dispatches.json not created (may be normal if no matching events)"
fi

# ============================================================
# Phase 6: Remote Tests (Optional)
# ============================================================
if $RUN_REMOTE; then
    echo ""
    echo "📋 Phase 6: Remote Machine Tests"
    echo "---"
    
    # epyc6
    echo "Testing epyc6..."
    EPYC_OUT=$(ssh feng@epyc6 'source ~/.zshenv && cd ~/agent-skills && git pull -q && python3 scripts/test-event-bus-e2e.py 2>&1' | grep "RESULTS" || echo "FAILED")
    if echo "$EPYC_OUT" | grep -q "6 passed"; then
        test_result 0 "epyc6: E2E test passed"
    else
        test_result 1 "epyc6: E2E test failed"
    fi
    
    # homedesktop-wsl
    echo "Testing homedesktop-wsl..."
    WSL_OUT=$(ssh -p 2222 fengning@100.109.231.123 'source ~/.zshenv && cd ~/agent-skills && git pull -q && python3 scripts/test-event-bus-e2e.py 2>&1' | grep "RESULTS" || echo "FAILED")
    if echo "$WSL_OUT" | grep -q "6 passed"; then
        test_result 0 "homedesktop-wsl: E2E test passed"
    else
        test_result 1 "homedesktop-wsl: E2E test failed"
    fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
echo "📊 Summary"
echo "========================================"
TOTAL=$((PASSED + FAILED))
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo "Total:  $TOTAL"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED${NC}"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    exit 1
fi
