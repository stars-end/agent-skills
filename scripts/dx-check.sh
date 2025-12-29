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

if "${SCRIPT_DIR}/dx-status.sh"; then
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
        "${SCRIPT_DIR}/dx-status.sh"
    else
        echo "Exiting without fix."
        exit 1
    fi
fi
