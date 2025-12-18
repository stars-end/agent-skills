#!/bin/bash
# dx-status.sh
# Agent Self-Check Tool.
# Returns 0 if healthy, 1 if action is needed.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RESET='\033[0m'

echo -e "${BLUE}🩺 Checking Agent Health...${RESET}"
ERRORS=0

check_file() {
    if [ -f "$1" ] || [ -L "$1" ]; then
        echo -e "${GREEN}✅ Found $1${RESET}"
    else
        echo -e "${RED}❌ Missing $1${RESET}"
        ERRORS=$((ERRORS+1))
    fi
}

check_binary() {
    if command -v "$1" >/dev/null 2>&1; then
         echo -e "${GREEN}✅ Binary found: $1${RESET}"
    else
         echo -e "${RED}❌ Binary missing: $1${RESET}"
         echo "   Run: 'npm install -g $1' or check installation guide."
         ERRORS=$((ERRORS+1))
    fi
}

# 1. Check Configs
echo "--- Core Configs ---"
check_file "$HOME/.ntm.yaml"
check_file "$HOME/.serena/config.toml"
check_file "$HOME/.cass/settings.json"

# 2. Check Hooks
echo "--- Git Hooks ---"
HOOK_FILE="$HOME/prime-radiant-ai/.git/hooks/pre-commit"
SCRIPT_FILE="$HOME/agent-skills/scripts/validate_beads.py"

if [ ! -f "$SCRIPT_FILE" ]; then
    echo -e "${RED}❌ Critical: validate_beads.py missing in agent-skills${RESET}"
    echo "   Fix: cd ~/agent-skills && git pull origin master"
    ERRORS=$((ERRORS+1))
elif [ -f "$HOOK_FILE" ]; then
    if grep -q "validate_beads" "$HOOK_FILE"; then
        echo -e "${GREEN}✅ Hook installed in prime-radiant-ai${RESET}"
    else
        echo -e "${RED}❌ Hook invalid in prime-radiant-ai${RESET}"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${RED}❌ Hook missing in prime-radiant-ai${RESET}"
    ERRORS=$((ERRORS+1))
fi

# 3. Check Binaries
echo "--- Required Tools ---"
check_binary "universal-skills"
if command -v cass >/dev/null 2>&1; then
    echo -e "${GREEN}✅ Binary found: cass${RESET}"
else
    echo -e "${YELLOW}⚠️  Binary missing: cass${RESET}"
    echo "   (Optional but recommended for memory retrieval)"
    # Warn only
fi

# 4. Invoke MCP Doctor
echo "--- MCP & Tooling Status ---"
if [ -f "$HOME/agent-skills/mcp-doctor/check.sh" ]; then
    export MCP_DOCTOR_STRICT=1
    if ! bash "$HOME/agent-skills/mcp-doctor/check.sh"; then
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${RED}❌ MCP Doctor script missing${RESET}"
    ERRORS=$((ERRORS+1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✨ SYSTEM READY. All systems nominal.${RESET}"
    exit 0
else
    echo -e "${RED}⚠️  SYSTEM UNHEALTHY. Found $ERRORS errors.${RESET}"
    echo -e "${YELLOW}💡 TROUBLESHOOTING: Read ~/agent-skills/memory/playbooks/99_TROUBLESHOOTING.md for fixes.${RESET}"
    exit 1
fi
