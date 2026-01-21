#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight IDE Check"
echo "======================="
echo

VM_LIST=("epyc6" "macmini" "homedesktop-wsl")
# Canonical IDE set (V4.2.1 - gemini-cli deprecated)
IDES=("antigravity" "claude-code" "codex-cli" "opencode")

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    # First check if SSH works
    if ! ssh -o ConnectTimeout=2 "$vm" "true" 2>/dev/null; then
        echo "⚠️  SSH unreachable - skipping"
        echo
        continue
    fi

    installed=0
    total=${#IDES[@]}

    for ide in "${IDES[@]}"; do
        if ssh "$vm" "command -v $ide" 2>/dev/null; then
            echo "✅ $ide: Installed"
            ((installed++))
        else
            echo "❌ $ide: NOT installed"
        fi
    done

    echo "   Summary: $installed/$total IDEs installed"
    echo
done

echo "======================="
