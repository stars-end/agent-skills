#!/usr/bin/env bash
# dx-doctor.sh - Diagnose and repair multi-agent coordinator issues
# Part of bd-agent-skills-4l0 implementation

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}🩺 Multi-Agent Coordination Doctor${RESET}"
echo ""

AGENTS_ROOT="${HOME}/agent-skills"
ISSUES_FOUND=0

# =============================================================================
# Diagnose Slack Connection
# =============================================================================
diagnose_slack() {
    echo -e "${BLUE}=== Slack Connection ===${RESET}"
    
    if [[ -z "$SLACK_BOT_TOKEN" ]]; then
        echo -e "${RED}❌ SLACK_BOT_TOKEN not set${RESET}"
        echo "   Fix: Add to ~/.zshenv: export SLACK_BOT_TOKEN=xoxb-..."
        ((ISSUES_FOUND++))
    else
        echo -e "${GREEN}✅ SLACK_BOT_TOKEN set${RESET}"
    fi
    
    if [[ -z "$SLACK_APP_TOKEN" ]]; then
        echo -e "${RED}❌ SLACK_APP_TOKEN not set${RESET}"
        echo "   Fix: Add to ~/.zshenv: export SLACK_APP_TOKEN=xapp-..."
        ((ISSUES_FOUND++))
    else
        echo -e "${GREEN}✅ SLACK_APP_TOKEN set${RESET}"
    fi
    
    if [[ -z "$SLACK_MCP_XOXB_TOKEN" ]]; then
        echo -e "${YELLOW}⚠️  SLACK_MCP_XOXB_TOKEN not set (needed for Slack MCP in sessions)${RESET}"
    else
        echo -e "${GREEN}✅ SLACK_MCP_XOXB_TOKEN set${RESET}"
    fi
}

# =============================================================================
# Diagnose OpenCode
# =============================================================================
diagnose_opencode() {
    echo ""
    echo -e "${BLUE}=== OpenCode Server ===${RESET}"
    
    if systemctl --user is-active opencode-server >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OpenCode server: running${RESET}"
        
        # Check health
        if curl -s http://localhost:4105/global/health 2>/dev/null | grep -q "healthy"; then
            echo -e "${GREEN}✅ OpenCode health: OK${RESET}"
        else
            echo -e "${RED}❌ OpenCode health: failed${RESET}"
            ((ISSUES_FOUND++))
        fi
        
        # Count sessions
        session_count=$(curl -s http://localhost:4105/session 2>/dev/null | jq 'length' 2>/dev/null || echo "?")
        echo "   Active sessions: ${session_count}"
    else
        echo -e "${RED}❌ OpenCode server: not running${RESET}"
        echo "   Fix: systemctl --user start opencode-server"
        ((ISSUES_FOUND++))
    fi
}

# =============================================================================
# Diagnose Coordinator
# =============================================================================
diagnose_coordinator() {
    echo ""
    echo -e "${BLUE}=== Slack Coordinator ===${RESET}"
    
    if systemctl --user is-active slack-coordinator >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Coordinator: running${RESET}"
        
        # Check recent logs for errors
        error_count=$(journalctl --user -u slack-coordinator -n 50 --no-pager 2>/dev/null | grep -c "ERROR" || echo "0")
        if [[ "$error_count" -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Recent errors: ${error_count}${RESET}"
            journalctl --user -u slack-coordinator -n 5 --no-pager | grep "ERROR" | head -3
        else
            echo -e "${GREEN}✅ No recent errors${RESET}"
        fi
    else
        echo -e "${RED}❌ Coordinator: not running${RESET}"
        echo "   Fix: systemctl --user start slack-coordinator"
        ((ISSUES_FOUND++))
    fi
}

# =============================================================================
# Diagnose Beads
# =============================================================================
diagnose_beads() {
    echo ""
    echo -e "${BLUE}=== Beads Sync ===${RESET}"
    
    if command -v bd >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Beads CLI: available${RESET}"
    else
        echo -e "${RED}❌ Beads CLI: not found${RESET}"
        ((ISSUES_FOUND++))
    fi
    
    # Check merge driver
    if git config --global --get merge.beads.driver >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Beads merge driver: configured${RESET}"
    else
        echo -e "${RED}❌ Beads merge driver: not configured${RESET}"
        echo "   Fix: git config --global merge.beads.driver 'bd merge %O %A %B %L %P'"
        ((ISSUES_FOUND++))
    fi
    
    # Check for uncommitted beads changes
    for repo in ~/affordabot ~/prime-radiant-ai ~/agent-skills; do
        if [[ -d "$repo/.beads" ]]; then
            if git -C "$repo" diff --name-only 2>/dev/null | grep -q ".beads/"; then
                echo -e "${YELLOW}⚠️  Uncommitted Beads changes in $repo${RESET}"
            fi
        fi
    done
}

# =============================================================================
# Diagnose Worktrees
# =============================================================================
diagnose_worktrees() {
    echo ""
    echo -e "${BLUE}=== Git Worktrees ===${RESET}"
    
    for repo in affordabot prime-radiant-ai; do
        wt_dir="${HOME}/${repo}-worktrees"
        if [[ -d "$wt_dir" ]]; then
            wt_count=$(find "$wt_dir" -maxdepth 1 -type d | wc -l)
            wt_count=$((wt_count - 1))
            echo "   ${repo}: ${wt_count} worktrees"
        else
            echo "   ${repo}: no worktree directory"
        fi
    done
}

# =============================================================================
# Repair Common Issues
# =============================================================================
repair_common() {
    echo ""
    echo -e "${BLUE}=== Attempting Repairs ===${RESET}"
    
    # Restart coordinator
    echo "   Restarting coordinator..."
    systemctl --user restart slack-coordinator 2>/dev/null || true
    
    # Ensure worktree directories exist
    mkdir -p ~/affordabot-worktrees
    mkdir -p ~/prime-radiant-worktrees
    
    # Configure beads merge driver
    git config --global merge.beads.driver "bd merge %O %A %B %L %P" 2>/dev/null || true
    
    echo -e "${GREEN}✅ Repairs attempted${RESET}"
}

# =============================================================================
# Main
# =============================================================================
diagnose_slack
diagnose_opencode
diagnose_coordinator
diagnose_beads
diagnose_worktrees

echo ""
if [[ "$ISSUES_FOUND" -eq 0 ]]; then
    echo -e "${GREEN}✨ All systems healthy!${RESET}"
else
    echo -e "${YELLOW}Found ${ISSUES_FOUND} issue(s)${RESET}"
    echo ""
    read -p "Attempt automatic repairs? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        repair_common
    fi
fi
