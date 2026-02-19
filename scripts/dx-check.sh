#!/bin/bash
# scripts/dx-check.sh
# Unified bootstrap command: Check health + Auto-fix.

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RESET='\033[0m'

# Resolve symlinks to get actual script directory (works on macOS and Linux)
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

echo -e "${BLUE}🩺 Running DX Health Check...${RESET}"

# V5/V6 Preflight: Prefer centralized Beads state, but don't hard-fail if it's discoverable.
DEFAULT_BEADS_DIR="$HOME/bd/.beads"
if [[ -z "${BEADS_DIR:-}" ]]; then
    if [[ -d "$DEFAULT_BEADS_DIR" ]]; then
        echo -e "${YELLOW}⚠️  BEADS_DIR not set; defaulting to ${DEFAULT_BEADS_DIR} for this run.${RESET}"
        echo "   Tip: persist with: export BEADS_DIR=\"$DEFAULT_BEADS_DIR\" (e.g. ~/.zshenv or ~/.bash_profile)"
        export BEADS_DIR="$DEFAULT_BEADS_DIR"
        export BEADS_IGNORE_REPO_MISMATCH=1
    else
        echo -e "${RED}❌ FATAL: BEADS_DIR not set and default DB not found.${RESET}"
        echo "   Expected Beads DB at: $DEFAULT_BEADS_DIR"
        echo "   Action:"
        echo "     1) Clone bd repo: git clone git@github.com:stars-end/bd.git ~/bd"
        echo "     2) Persist: export BEADS_DIR=\"$DEFAULT_BEADS_DIR\""
        echo "     3) Persist: export BEADS_IGNORE_REPO_MISMATCH=1"
        exit 1
    fi
fi

# Ensure mismatch bypass is set if using centralized DB
if [[ "${BEADS_DIR}" == "${DEFAULT_BEADS_DIR}" ]]; then
    export BEADS_IGNORE_REPO_MISMATCH=1
fi

if [[ -d ".beads" ]]; then
    echo -e "${YELLOW}⚠️  Encountered local .beads/ directory (DEPRECATED)${RESET}"
    echo "   V5 requires this to be removed. Deleting..."
    rm -rf .beads
fi

# Freshness Check for AGENTS.md
if [ -f "AGENTS.local.md" ]; then
    get_hash() {
        if command -v md5sum >/dev/null 2>&1; then
            md5sum "$1" | cut -d' ' -f1
        else
            md5 -q "$1"
        fi
    }

    GLOBAL_SRC=~/agent-skills/AGENTS.md
    if [ -f "$GLOBAL_SRC" ]; then
        GLOBAL_HASH=$(get_hash "$GLOBAL_SRC")
        LOCAL_HASH=$(get_hash "AGENTS.local.md")
        
        COMPILED_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'global-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")
        COMPILED_LOCAL_HASH=$(head -n 5 AGENTS.md 2>/dev/null | grep -o 'local-hash:[a-f0-9]*' | cut -d: -f2 || echo "none")

        if [ "$GLOBAL_HASH" != "$COMPILED_HASH" ] || [ "$LOCAL_HASH" != "$COMPILED_LOCAL_HASH" ]; then
            echo -e "${BLUE}⚠️  AGENTS.md stale - recompiling...${RESET}"
            "${SCRIPT_DIR}/compile_agent_context.sh" .
        fi
    fi
fi

needs_fix=0
if ! "${SCRIPT_DIR}/dx-status.sh"; then
    needs_fix=1
fi

# External Beads repo must be git-synced (durability across VMs)
if [[ "${BEADS_DIR}" == "${DEFAULT_BEADS_DIR}" ]]; then
    if [[ ! -d "$HOME/bd/.git" ]]; then
        echo -e "${RED}❌ FATAL: BEADS_DIR points at $DEFAULT_BEADS_DIR but ~/bd is not a git repo.${RESET}"
        echo "   Action:"
        echo "     1) Clone bd repo: git clone git@github.com:stars-end/bd.git ~/bd"
        echo "     2) Configure remote sync: git -C ~/bd remote add origin git@github.com:stars-end/bd.git"
        needs_fix=1
    elif ! git -C "$HOME/bd" remote get-url origin >/dev/null 2>&1; then
        echo -e "${RED}❌ FATAL: ~/bd has no 'origin' remote. Beads state will not sync across VMs.${RESET}"
        echo "   Fix:"
        echo "     git -C ~/bd remote add origin git@github.com:stars-end/bd.git"
        echo "     git -C ~/bd push -u origin master"
        needs_fix=1
    fi
fi

# WIP Branch Check
if [ -f "${SCRIPT_DIR}/dx-wip-check.sh" ]; then
    "${SCRIPT_DIR}/dx-wip-check.sh"
fi

if [ "$needs_fix" -eq 0 ]; then
    echo -e "${GREEN}✨ Environment is healthy.${RESET}"
else
    echo -e "${RED}⚠️  Environment unhealthy.${RESET}"
    
    # Check for TTY or NO_PROMPT override
    if [ -t 0 ] && [ "${DX_CHECK_NO_PROMPT:-0}" != "1" ]; then
        read -p "Run auto-fix (hydrate)? [Y/n]: " run_fix
    else
        echo -e "${BLUE}ℹ Non-interactive mode detected. Auto-fixing...${RESET}"
        run_fix="y"
    fi

    if [[ $run_fix =~ ^[Yy] ]] || [[ -z $run_fix ]]; then
        "${SCRIPT_DIR}/dx-hydrate.sh"
        echo -e "${BLUE}🔄 Re-checking status...${RESET}"
        if ! "${SCRIPT_DIR}/dx-status.sh"; then
            exit 1
        fi
    else
        echo "Exiting without fix."
        exit 1
    fi
fi
