#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight Railway CLI Check"
echo "================================="
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

    # Check railway CLI exists
    if ! ssh "$vm" "command -v railway" 2>/dev/null; then
        echo "❌ railway CLI NOT installed"
        echo "   Install: npm install -g @railway/cli"
        echo
        continue
    fi

    echo "✅ railway CLI installed"

    # Check if logged in
    if ssh "$vm" "railway status &>/dev/null"; then
        echo "✅ railway CLI logged in"
        # Show project info
        ssh "$vm" "railway status 2>&1 | head -5" || true
    else
        echo "❌ railway CLI NOT logged in"
        echo "   Fix: railway login"
    fi

    echo
done

echo "================================="
