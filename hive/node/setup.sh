#!/usr/bin/env bash
# hive/node/setup.sh
# Provisions a host to act as a Hive Node (Agent Swarm Member)
# Idempotent.

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

HIVE_ROOT="$HOME/.agent-hive"
PODS_ROOT="/tmp/pods"
REPOS_ROOT="$HOME/repos"

echo -e "${GREEN}🐝 Provisioning Hive Node...${RESET}"

# 1. Directory Structure
echo " -> Creating directories..."
mkdir -p "$HIVE_ROOT" "$PODS_ROOT" "$REPOS_ROOT"
chmod 700 "$PODS_ROOT"

# 2. Dependency Checks
echo " -> Verifying required tools..."

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ Missing required tool: $1${RESET}"
        return 1
    else
        echo -e "${GREEN}✅ Found $1${RESET}"
        return 0
    fi
}

REQUIRED_TOOLS=(git python3 zsh)
MISSING=0

for tool in "${REQUIRED_TOOLS[@]}"; do
    check_tool "$tool" || MISSING=1
done

# Special Check for Beads (bd)
if ! command -v bd &> /dev/null; then
     echo -e "${YELLOW}⚠️  'bd' (Beads) not found.${RESET}"
     echo "    Install via: pip install beads-cli (or check AGENTS.md)"
     MISSING=1
else
     echo -e "${GREEN}✅ Found bd${RESET}"
fi

# Special Check for Cass (Long-term Memory)
if ! command -v cass &> /dev/null; then
     echo -e "${YELLOW}⚠️  'cass' not found.${RESET}"
     echo "    Install via: cargo build --release (see TECH_PLAN.md)"
     MISSING=1
else
     echo -e "${GREEN}✅ Found cass${RESET}"
fi

# Special Check for Claude/Auth (Env Check)
# We can't easily check for the alias 'cc-glm' since it's in .zshrc, 
# but we can check if .zshrc exists.
if [ ! -f "$HOME/.zshrc" ]; then
    echo -e "${RED}❌ No ~/.zshrc found. Agent needs Z.ai env vars.${RESET}"
    MISSING=1
fi

if [ "$MISSING" -eq 1 ]; then
    echo -e "${RED}🛑 Provisioning failed due to missing dependencies.${RESET}"
    exit 1
fi

# 3. Ledger Initialization
if [ ! -f "$HIVE_ROOT/ledger.json" ]; then
    echo '{"sessions": {}, "nodes": {}}' > "$HIVE_ROOT/ledger.json"
    echo -e "${GREEN}✅ Initialized ledger at $HIVE_ROOT/ledger.json${RESET}"
else
    echo -e "${GREEN}✅ Ledger exists.${RESET}"
fi

# 4. Hydration (Tool Linking)
if [ -f "./scripts/dx-hydrate.sh" ]; then
    echo " -> Running dx-hydrate.sh to link tools..."
    ./scripts/dx-hydrate.sh
fi

echo -e "    Current User: $(whoami)"
echo -e "${GREEN}✨ Node Provisioning Complete.${RESET}"