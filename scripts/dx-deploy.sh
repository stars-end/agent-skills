#!/usr/bin/env bash
# dx-deploy.sh - Deploy multi-agent coordinator to all VMs
# Part of bd-agent-skills-4l0 implementation

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}🚀 Multi-Agent Coordinator Deployment${RESET}"
echo ""

# Configuration
TARGET_VMS="${TARGET_VMS:-epyc6 macmini}"
AGENTS_REPO="agent-skills"

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${RESET}"
fi

for vm in $TARGET_VMS; do
    echo ""
    echo -e "${BLUE}=== Deploying to ${vm} ===${RESET}"
    
    if $DRY_RUN; then
        echo "   [DRY RUN] Would deploy to ${vm}"
        continue
    fi
    
    # Check connectivity
    if ! ssh -o ConnectTimeout=5 "$vm" 'echo connected' >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot connect to ${vm}${RESET}"
        continue
    fi
    
    # Pull latest code
    echo "   Pulling latest code..."
    ssh "$vm" "cd ~/${AGENTS_REPO} && git pull origin master" || {
        echo -e "${YELLOW}⚠️  Git pull failed, trying force checkout${RESET}"
        ssh "$vm" "cd ~/${AGENTS_REPO} && git fetch origin && git checkout -f origin/master"
    }
    
    # Run hydration
    echo "   Running hydration..."
    ssh "$vm" "~/${AGENTS_REPO}/scripts/dx-hydrate.sh" 2>/dev/null || true
    
    # Restart OpenCode server
    echo "   Restarting OpenCode server..."
    ssh "$vm" 'systemctl --user restart opencode-server' 2>/dev/null || {
        echo -e "${YELLOW}⚠️  OpenCode restart failed, may not be installed${RESET}"
    }
    
    # Restart coordinator
    echo "   Restarting coordinator..."
    ssh "$vm" 'systemctl --user restart slack-coordinator' 2>/dev/null || {
        echo -e "${YELLOW}⚠️  Coordinator restart failed, may not be installed${RESET}"
    }
    
    # Verify health
    echo "   Verifying health..."
    sleep 2
    
    if ssh "$vm" 'systemctl --user is-active slack-coordinator' >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Coordinator running${RESET}"
    else
        echo -e "${RED}   ❌ Coordinator not running${RESET}"
    fi
    
    if ssh "$vm" 'systemctl --user is-active opencode-server' >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ OpenCode running${RESET}"
    else
        echo -e "${RED}   ❌ OpenCode not running${RESET}"
    fi
done

echo ""
echo -e "${GREEN}✨ Deployment complete${RESET}"
echo ""
echo "Next steps:"
echo "  1. Post test message to #affordabot-agents"
echo "  2. Check: journalctl --user -u slack-coordinator -f"
