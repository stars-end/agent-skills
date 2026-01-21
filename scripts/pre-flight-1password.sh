#!/bin/bash
set -euo pipefail

echo "🔍 Pre-Flight 1Password CLI Check"
echo "==================================="
echo

VM_LIST=("epyc6" "macmini" "homedesktop-wsl")
required_version="2.18.0"

for vm in "${VM_LIST[@]}"; do
    echo "=== $vm ==="

    # First check if SSH works
    if ! ssh -o ConnectTimeout=2 "$vm" "true" 2>/dev/null; then
        echo "⚠️  SSH unreachable - skipping"
        echo
        continue
    fi

    # Check if op CLI exists
    if ! ssh "$vm" "command -v op" 2>/dev/null; then
        echo "❌ op CLI NOT installed"
        echo "   Install: brew install 1password-cli"
        echo
        continue
    fi

    # Check version
    version=$(ssh "$vm" "op --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo '0.0.0'")

    if [ "$version" = "0.0.0" ]; then
        echo "⚠️  op CLI installed but version check failed"
        echo "   Manual check: ssh $vm 'op --version'"
    elif [ "$(printf '%s\n' "$required_version" "$version" | sort -V | head -n1)" != "$required_version" ]; then
        echo "❌ op CLI version $version (< $required_version)"
        echo "   Upgrade: brew upgrade 1password-cli"
    else
        echo "✅ op CLI version: $version"

        # Check authentication
        if ssh "$vm" "op whoami &>/dev/null"; then
            echo "✅ op CLI authenticated (account auth)"
        else
            echo "ℹ️  op CLI NOT authenticated (OK - will use service account)"
        fi
    fi

    echo
done

echo "==================================="
