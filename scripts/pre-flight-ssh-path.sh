#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight SSH PATH Check"
echo "=============================="
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

    # Check if op CLI is in SSH PATH
    if ssh "$vm" "command -v op" 2>/dev/null; then
        echo "✅ op CLI in SSH PATH"

        # Show SSH PATH
        ssh_path=$(ssh "$vm" "echo \$PATH" 2>/dev/null)
        echo "   SSH PATH: $ssh_path"
    else
        echo "❌ op CLI NOT in SSH PATH"

        # Show SSH PATH for debugging
        ssh_path=$(ssh "$vm" "echo \$PATH" 2>/dev/null || echo "unable to determine")
        echo "   SSH PATH: $ssh_path"
        echo ""
        echo "   Fix: Add to ~/.zshenv (NOT ~/.zshrc):"
        echo '   export PATH="/usr/local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin:$PATH"'
    fi

    # Check if ~/.agent/skills exists
    if ssh "$vm" "[ -d ~/.agent/skills ]" 2>/dev/null; then
        echo "✅ ~/.agent/skills exists"
    else
        echo "⚠️  ~/.agent/skills NOT found (will be created)"
    fi

    echo
done

echo "=============================="
