#!/bin/bash
# scripts/dx-check.sh
# Unified bootstrap command: Check health + Auto-fix.

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}🩺 Running DX Health Check...${RESET}"

AUTO_CHECKPOINT_INSTALLER=""
if command -v auto-checkpoint-install >/dev/null 2>&1; then
    AUTO_CHECKPOINT_INSTALLER="$(command -v auto-checkpoint-install)"
elif [ -f "${SCRIPT_DIR}/auto-checkpoint-install.sh" ]; then
    AUTO_CHECKPOINT_INSTALLER="${SCRIPT_DIR}/auto-checkpoint-install.sh"
fi

needs_fix=0
if ! "${SCRIPT_DIR}/dx-status.sh"; then
    needs_fix=1
fi

# Auto-checkpoint scheduling is REQUIRED for durability. This is enforced in dx-check (not dx-status),
# so dx-status can remain usable for partial environments and optional stacks.
if [ -n "$AUTO_CHECKPOINT_INSTALLER" ]; then
    if ! "$AUTO_CHECKPOINT_INSTALLER" --status --check >/dev/null 2>&1; then
        echo -e "${RED}❌ auto-checkpoint scheduler not active (required)${RESET}"
        "$AUTO_CHECKPOINT_INSTALLER" --status || true
        needs_fix=1
    fi
else
    echo -e "${RED}❌ auto-checkpoint-install not found (required)${RESET}"
    echo "   Fix: run: ${SCRIPT_DIR}/dx-ensure-bins.sh"
    needs_fix=1
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
        if [ -n "$AUTO_CHECKPOINT_INSTALLER" ]; then
            "$AUTO_CHECKPOINT_INSTALLER" >/dev/null 2>&1 || true
        fi
        echo -e "${BLUE}🔄 Re-checking status...${RESET}"
        "${SCRIPT_DIR}/dx-status.sh" || true
        if [ -n "$AUTO_CHECKPOINT_INSTALLER" ] && ! "$AUTO_CHECKPOINT_INSTALLER" --status --check >/dev/null 2>&1; then
            echo -e "${RED}❌ auto-checkpoint scheduler still not active${RESET}"
            "$AUTO_CHECKPOINT_INSTALLER" --status || true
            exit 1
        fi
    else
        echo "Exiting without fix."
        exit 1
    fi
fi
