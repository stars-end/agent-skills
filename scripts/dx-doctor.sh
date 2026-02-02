#!/usr/bin/env bash
# dx-doctor.sh - Diagnose and repair multi-agent coordinator issues
# Enhanced for cross-VM, cross-agent, and MCP verification (V4.2+)

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

TARGET_VM="${1:-local}"
AGENTS_ROOT="${HOME}/agent-skills"
ISSUES_FOUND=0

# =============================================================================
# Helper: Check MCP Servers
# =============================================================================
check_mcp_servers() {
    echo -e "${BLUE}=== MCP Servers (Claude) ===${RESET}"
    
    # Get current MCP list
    local mcp_list
    mcp_list=$(claude mcp list 2>/dev/null || echo "")

    for mcp in "slack" "figma" "supermemory"; do
        if echo "$mcp_list" | grep -q "$mcp"; then
            if echo "$mcp_list" | grep "$mcp" | grep -q "✓"; then
                echo -e "${GREEN}✅ MCP healthy: $mcp${RESET}"
            else
                echo -e "${RED}❌ MCP unhealthy: $mcp${RESET}"
                ((ISSUES_FOUND++))
            fi
        else
            if [[ "$mcp" == "figma" || "$mcp" == "supermemory" ]]; then
                echo -e "${YELLOW}⚠️  Optional MCP missing: $mcp${RESET}"
            else
                echo -e "${RED}❌ Required MCP missing: $mcp${RESET}"
                ((ISSUES_FOUND++))
            fi
        fi
    done
}

# =============================================================================
# Diagnose Local VM
# =============================================================================
diagnose_local() {
    # Load environment if available
    if [[ -f "$HOME/.agent-env" ]]; then
        source "$HOME/.agent-env"
    fi

    echo -e "${BLUE}🩺 Local System Doctor (${HOSTNAME})${RESET}"
    echo ""

    # 1. Slack Connection
    echo -e "${BLUE}=== Slack Connection ===${RESET}"
    for var in "SLACK_BOT_TOKEN" "SLACK_APP_TOKEN"; do
        if [[ -z "${!var:-}" ]]; then
            echo -e "${RED}❌ $var not set${RESET}"
            ((ISSUES_FOUND++))
        else
            echo -e "${GREEN}✅ $var set${RESET}"
        fi
    done

    # 2. OpenCode
    echo ""
    echo -e "${BLUE}=== OpenCode Server ===${RESET}"
    
    if command -v systemctl >/dev/null 2>&1; then
        # Linux/Systemd check
        if systemctl --user is-active opencode.service >/dev/null 2>&1; then
            echo -e "${GREEN}✅ OpenCode server: running${RESET}"
        else
            echo -e "${RED}❌ OpenCode server: not running${RESET}"
            ((ISSUES_FOUND++))
        fi
    elif command -v launchctl >/dev/null 2>&1; then
        # macOS/Launchd check
        if launchctl list | grep -q "com.agent.opencode-server"; then
            echo -e "${GREEN}✅ OpenCode server: running (launchd)${RESET}"
        else
            echo -e "${RED}❌ OpenCode server: not running${RESET}"
            ((ISSUES_FOUND++))
        fi
    fi

    # Health check (common)
    if curl -s http://localhost:4105/global/health 2>/dev/null | grep -q "healthy"; then
        echo -e "${GREEN}✅ OpenCode health: OK${RESET}"
    else
        echo -e "${RED}❌ OpenCode health: failed${RESET}"
        ((ISSUES_FOUND++))
    fi

    # 3. Coordinator
    echo ""
    echo -e "${BLUE}=== Slack Coordinator ===${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl --user is-active slack-coordinator.service >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Coordinator: running${RESET}"
        else
            echo -e "${RED}❌ Coordinator: not running${RESET}"
            ((ISSUES_FOUND++))
        fi
    elif command -v launchctl >/dev/null 2>&1; then
        if launchctl list | grep -q "com.starsend.slack-coordinator"; then
            echo -e "${GREEN}✅ Coordinator: running (launchd)${RESET}"
        else
            echo -e "${RED}❌ Coordinator: not running${RESET}"
            ((ISSUES_FOUND++))
        fi
    fi

    # 4. MCP Servers
    echo ""
    check_mcp_servers

    # 5. Beads (V5 Enhanced)
    echo ""
    echo -e "${BLUE}=== Beads (V5) ===${RESET}"
    if [[ -z "${BEADS_DIR:-}" ]]; then
        echo -e "${RED}❌ BEADS_DIR not set${RESET}"
        ((ISSUES_FOUND++))
    else
        echo -e "${GREEN}✅ BEADS_DIR set: $BEADS_DIR${RESET}"
        if [[ ! -d "$BEADS_DIR" ]]; then
            echo -e "${RED}❌ BEADS_DIR directory missing: $BEADS_DIR${RESET}"
            ((ISSUES_FOUND++))
        fi
    fi

    if [[ -d ".beads" ]]; then
        echo -e "${RED}❌ Local .beads/ directory exists (V5 violation)${RESET}"
        echo -e "${YELLOW}   Repair: rm -rf .beads${RESET}"
        ((ISSUES_FOUND++))
    fi

    if command -v bd >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Beads CLI available${RESET}"
    else
        echo -e "${RED}❌ Beads CLI missing${RESET}"
        ((ISSUES_FOUND++))
    fi
}

# =============================================================================
# Main
# =============================================================================
if [[ "$TARGET_VM" == "@all" ]]; then
    # Read keys and ssh fields from json
    while IFS="=" read -r key ssh_target; do
        if [[ "$key" != "epyc6" ]]; then
            echo -e "${BLUE}--- Checking $key ---${RESET}"
            # Use the explicit SSH target (user@host) from json
            ssh "$ssh_target" "bash -s" < "$0" "local" || echo -e "${RED}Failed to check $key${RESET}"
            echo ""
        fi
    done < <(jq -r '.vms | to_entries[] | "\(.key)=\(.value.ssh)"' ~/.agent-skills/vm-endpoints.json)
elif [[ "$TARGET_VM" == "local" || -z "$TARGET_VM" ]]; then
    diagnose_local
    if [[ "$ISSUES_FOUND" -eq 0 ]]; then
        echo -e "\n${GREEN}✨ System healthy!${RESET}"
    else
        echo -e "\n${YELLOW}Found ${ISSUES_FOUND} issue(s)${RESET}"
    fi
else
    # Remote VM by name
    ssh "$TARGET_VM" "bash -s" < "$0" "local"
fi