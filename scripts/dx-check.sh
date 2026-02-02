#!/bin/bash
# scripts/dx-check.sh
# Unified bootstrap command: Check health + Auto-fix.

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# V5 Preflight: Enforce BEADS_DIR
if [[ -z "${BEADS_DIR:-}" ]]; then
    echo -e "${RED}❌ FATAL: BEADS_DIR not set in environment.${RESET}"
    echo "   V5 REQUIREMENT: All Beads state must live in a centralized directory."
    echo "   Action: Add 'export BEADS_DIR=/home/fengning/bd/.beads' to your .zshrc"
    exit 1
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

resolve_auto_checkpoint_installer() {
    if command -v auto-checkpoint-install >/dev/null 2>&1; then
        command -v auto-checkpoint-install
        return 0
    fi
    if [ -f "${SCRIPT_DIR}/auto-checkpoint-install.sh" ]; then
        echo "${SCRIPT_DIR}/auto-checkpoint-install.sh"
        return 0
    fi
    echo ""
    return 1
}

check_auto_checkpoint_scheduler() {
    local installer="$1"
    if [ -z "$installer" ]; then
        return 1
    fi
    "$installer" --status --check >/dev/null 2>&1
}

needs_fix=0
if ! "${SCRIPT_DIR}/dx-status.sh"; then
    needs_fix=1
fi

# Auto-checkpoint scheduling is REQUIRED for durability. This is enforced in dx-check (not dx-status),
# so dx-status remains usable for partial environments.
AUTO_CHECKPOINT_INSTALLER="$(resolve_auto_checkpoint_installer || true)"
if [ -z "$AUTO_CHECKPOINT_INSTALLER" ]; then
    echo -e "${RED}❌ auto-checkpoint-install not found (required)${RESET}"
    echo "   Fix: run: ${SCRIPT_DIR}/dx-ensure-bins.sh"
    needs_fix=1
elif ! check_auto_checkpoint_scheduler "$AUTO_CHECKPOINT_INSTALLER"; then
    echo -e "${RED}❌ auto-checkpoint scheduler not active (required)${RESET}"
    "$AUTO_CHECKPOINT_INSTALLER" --status || true
    needs_fix=1
fi

# WIP Branch Check - warn about unmerged auto-checkpoint branches
if [ -f "${SCRIPT_DIR}/dx-wip-check.sh" ]; then
    "${SCRIPT_DIR}/dx-wip-check.sh"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "BEADS_DIR Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ -z "$BEADS_DIR" ]]; then
    echo "❌ BEADS_DIR not set"
    echo "   Run: cd ~/agent-skills && ./scripts/migrate-to-external-beads.sh"
    needs_fix=1
elif [[ ! -d "$BEADS_DIR" ]]; then
    echo "❌ BEADS_DIR points to non-existent directory: $BEADS_DIR"
    needs_fix=1
elif [[ ! -f "$BEADS_DIR/beads.db" ]]; then
    echo "⚠️  BEADS_DIR set but database doesn't exist: $BEADS_DIR"
    echo "   Run: cd ~/agent-skills && ./scripts/migrate-to-external-beads.sh"
else
    echo "✅ BEADS_DIR configured: $BEADS_DIR"
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

        # Ensure auto-checkpoint scheduler is installed/enabled even if dx-hydrate best-effort failed.
        AUTO_CHECKPOINT_INSTALLER="$(resolve_auto_checkpoint_installer || true)"
        if [ -n "$AUTO_CHECKPOINT_INSTALLER" ]; then
            "$AUTO_CHECKPOINT_INSTALLER" >/dev/null 2>&1 || true
        fi

        echo -e "${BLUE}🔄 Re-checking status...${RESET}"
        if ! "${SCRIPT_DIR}/dx-status.sh"; then
            exit 1
        fi
        AUTO_CHECKPOINT_INSTALLER="$(resolve_auto_checkpoint_installer || true)"
        if [ -z "$AUTO_CHECKPOINT_INSTALLER" ] || ! check_auto_checkpoint_scheduler "$AUTO_CHECKPOINT_INSTALLER"; then
            echo -e "${RED}❌ auto-checkpoint scheduler still not active${RESET}"
            [ -n "$AUTO_CHECKPOINT_INSTALLER" ] && "$AUTO_CHECKPOINT_INSTALLER" --status || true
            exit 1
        fi
    else
        echo "Exiting without fix."
        exit 1
    fi
fi
