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
AGENTS_REPO="agent-skills"
# Resolve symlinks to get actual script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
# shellcheck disable=SC1090
source "$SCRIPT_DIR/canonical-targets.sh" 2>/dev/null || true

# Default targets (canonical host keys)
TARGET_VMS="${TARGET_VMS:-epyc6 macmini}"

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${RESET}"
fi

run_ssh() {
    local target="$1"
    shift
    if command -v ssh_canonical_vm >/dev/null 2>&1; then
        ssh_canonical_vm "$target" "$@"
    else
        ssh "$target" "$@"
    fi
}

for vm_key in $TARGET_VMS; do
    echo ""
    echo -e "${BLUE}=== Deploying to ${vm_key} ===${RESET}"
    
    if $DRY_RUN; then
        echo "   [DRY RUN] Would deploy to ${vm_key}"
        continue
    fi
    
    # Resolve vm_key to canonical SSH target (user@host)
    vm_target=""
    if declare -p CANONICAL_VMS >/dev/null 2>&1; then
        for entry in "${CANONICAL_VMS[@]}"; do
            host="${entry%%:*}"
            host_key="${host#*@}"
            if [[ "$host_key" == "$vm_key" ]]; then
                vm_target="$host"
                break
            fi
        done
    fi
    vm_target="${vm_target:-$vm_key}"

    # Check connectivity
    if ! run_ssh "$vm_target" 'echo connected' >/dev/null 2>&1; then
        echo -e "${RED}❌ Cannot connect to ${vm_target}${RESET}"
        continue
    fi
    
    # Pull latest code
    echo "   Pulling latest code..."
    run_ssh "$vm_target" "cd ~/${AGENTS_REPO} && git pull origin master" || {
        echo -e "${YELLOW}⚠️  Git pull failed, trying force checkout${RESET}"
        run_ssh "$vm_target" "cd ~/${AGENTS_REPO} && git fetch origin && git checkout -f origin/master"
    }
    
    # Run hydration
    echo "   Running hydration..."
    run_ssh "$vm_target" "~/${AGENTS_REPO}/scripts/dx-hydrate.sh" 2>/dev/null || true
    
    # Restart OpenCode server
    echo "   Restarting OpenCode server..."
    run_ssh "$vm_target" 'systemctl --user restart opencode 2>/dev/null || systemctl --user restart opencode-server 2>/dev/null || true'
    
    # Restart coordinator
    echo "   Restarting coordinator..."
    run_ssh "$vm_target" 'systemctl --user restart slack-coordinator 2>/dev/null || true'
    
    # Verify health
    echo "   Verifying health..."
    sleep 2
    
    if run_ssh "$vm_target" 'systemctl --user is-active slack-coordinator' >/dev/null 2>&1; then
        echo -e "${GREEN}   ✅ Coordinator running${RESET}"
    else
        echo -e "${RED}   ❌ Coordinator not running${RESET}"
    fi
    
    if run_ssh "$vm_target" 'systemctl --user is-active opencode 2>/dev/null || systemctl --user is-active opencode-server' >/dev/null 2>&1; then
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
