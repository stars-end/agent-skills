#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight GH CLI Check"
echo "==========================="
echo

VM_LIST=("epyc6" "macmini" "homedesktop-wsl")

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    # First check if SSH works
    if ! ssh -o ConnectTimeout=2 "$vm" "true" 2>/dev/null; then
        echo "⚠️  SSH unreachable - skipping"
        echo
        continue
    fi

    # Check gh CLI exists
    if ! ssh "$vm" "command -v gh" 2>/dev/null; then
        echo "❌ gh CLI NOT installed"
        echo "   Install: brew install gh"
        echo
        continue
    fi

    echo "✅ gh CLI installed"

    # Check if logged in
    if ssh "$vm" "gh auth status &>/dev/null"; then
        echo "✅ gh CLI logged in"
        # Show auth status
        ssh "$vm" "gh auth status 2>&1 | head -3" || true
    else
        echo "❌ gh CLI NOT logged in"
        echo "   Fix: gh auth login"
    fi

    echo
done

echo "==========================="
