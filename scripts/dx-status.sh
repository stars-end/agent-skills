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

# Cross-platform realpath
resolve_path() {
    python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"
}

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
# NOTE: serena is deprecated (V4.2.1) - removed from checks
check_file "$HOME/.cass/settings.json"

# Check local GEMINI symlink if we are inside a repo
if [ -f AGENTS.md ]; then
    if [ -L "GEMINI.md" ] && [ "$(readlink GEMINI.md)" = "AGENTS.md" ]; then
        echo -e "${GREEN}✅ GEMINI.md -> AGENTS.md linked${RESET}"
    else
        echo -e "${YELLOW}⚠️  GEMINI.md symlink missing or invalid in current dir${RESET}"
        # Warn only, as we might be running from /tmp
    fi
fi

# 2. Check Hooks (V3 Logic)
echo "--- Git Hooks ---"
PRIME_HOOK="$HOME/prime-radiant-ai/.git/hooks/pre-commit"

# Check if hook exists (symlink or file)
if [ -e "$PRIME_HOOK" ]; then
    IS_VALID=0
    
    # Method A: V3 Symlink
    if [ -L "$PRIME_HOOK" ]; then
        TARGET=$(resolve_path "$PRIME_HOOK")
        if [[ "$TARGET" == *"permission-sentinel"* ]]; then
            IS_VALID=1
        fi
    fi
    
    # Method B: Legacy/Content Check
    if [ $IS_VALID -eq 0 ] && [ -f "$PRIME_HOOK" ]; then
        if grep -q "validate_beads" "$PRIME_HOOK" 2>/dev/null; then
            IS_VALID=1
        elif grep -q "permission-sentinel" "$PRIME_HOOK" 2>/dev/null; then
            IS_VALID=1
        fi
    fi

    if [ $IS_VALID -eq 1 ]; then
        echo -e "${GREEN}✅ Hook installed in prime-radiant-ai${RESET}"
    else
        echo -e "${RED}❌ Hook invalid in prime-radiant-ai${RESET}"
        echo "   Target: $(resolve_path $PRIME_HOOK)"
        echo "   Fix: Run ~/agent-skills/git-safety-guard/install.sh"
        ERRORS=$((ERRORS+1))
    fi
else
    echo -e "${RED}❌ Hook missing in prime-radiant-ai${RESET}"
    echo "   Fix: Run ~/agent-skills/git-safety-guard/install.sh"
    ERRORS=$((ERRORS+1))
fi

# 3. Check Binaries
echo "--- Required Tools ---"
check_binary "bd"
check_binary "jules"
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
